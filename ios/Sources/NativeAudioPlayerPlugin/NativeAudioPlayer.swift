import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@objc public class NativeAudioPlayer: NSObject, AVAudioPlayerDelegate {

    var playerItems: [AudioPlayerItem] = []
    var audioPlayer: AVAudioPlayer?
    var currentIndex: Int = 0
    var earpiece: Bool = true

    // the item currentIndex points at, or nil while the playlist is empty --
    // everything below reads through this so an unset playlist cannot trap
    var currentItem: AudioPlayerItem? {
        playerItems.indices.contains(currentIndex) ? playerItems[currentIndex] : nil
    }
    var currentId: String {
        currentItem?.id ?? ""
    }
    var duration: Int {
        Int(audioPlayer?.duration ?? 0)
    }
    var position: Int {
        Int(audioPlayer?.currentTime ?? 0)
    }
    /// What the lock screen is told about the speed of playback.
    ///
    /// It is not decoration: the system runs its own clock from the elapsed time it was last
    /// given, advancing it at this rate, and draws the transport button from it -- a non-zero
    /// rate means playing, so it offers pause. A rate left at 1.0 on a paused player therefore
    /// keeps offering pause, and the play command can never be reached from the lock screen.
    var playbackRate: Double {
        audioPlayer?.isPlaying == true ? 1.0 : 0.0
    }
    var title: String {
        currentItem?.title ?? ""
    }
    var subtitle: String {
        currentItem?.subtitle ?? ""
    }
    var onCompleted: ((_ id: String) -> Void)?

    var onAudioOutputChanged: ((_ output: String) -> Void)?

    /// The output the session is routed to right now, which is not necessarily the one that
    /// was requested: the earpiece/speaker override is skipped while an external device is
    /// connected, see `load()`.
    var audioOutput: String {
        NativeAudioPlayer.audioOutput(for: AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType)
    }

    static func audioOutput(for portType: AVAudioSession.Port?) -> String {
        switch portType {
        case .builtInReceiver:
            return "earpiece"
        case .builtInSpeaker:
            return "speaker"
        default:
            return "external"
        }
    }

    init(_ items: [[String: Any]]) {
        for item in items {
            let playerItem = AudioPlayerItem()
            playerItem.id = item["id"] as? String ?? ""
            playerItem.title = item["title"] as? String ?? ""
            playerItem.subtitle = item["subtitle"] as? String ?? ""
            playerItem.audioUri = item["audioUri"] as? String ?? ""
            playerItem.imageUri = item["imageUri"] as? String ?? ""
            playerItems.append(playerItem)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        // only tear down when this instance still owns a player: an instance that
        // never loaded must not deactivate the session or clear the lock screen
        // that a different instance has since taken over
        if audioPlayer != nil {
            stop()
        }
    }

    /// Starts reporting output changes, both the ones this plugin causes and the ones the
    /// user causes by plugging in headphones or connecting a bluetooth device.
    func observeAudioOutput() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        // Only a device the user connected or disconnected is an output change. load() sets the
        // category and the port override, and both raise this notification as well -- acting on
        // those would have start(), next() and select() pause the playback they just prepared.
        let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt

        guard reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
            || reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else {
            return
        }

        notifyAudioOutputChange()
    }

    /// Reports the output the audio is on now, and stops the playback that was going somewhere
    /// else.
    ///
    /// Every device change is reported, including one that leaves the answer as it was --
    /// swapping one bluetooth device for another is still a different device, and an app that
    /// names the output has something new to say about it.
    func notifyAudioOutputChange() {
        // audio that was going to the earpiece must not carry on out loud once the route
        // changed, so playback stops on every output change and the app decides whether to
        // resume
        pause()

        onAudioOutputChanged?(audioOutput)
    }

    // Capacitor's Filesystem API hands back fully qualified file:// URLs, but a
    // plain path is just as valid -- accept both instead of rebuilding the path
    // from its last component, which only ever resolved for Directory.Data.
    private func resolveURL(_ uri: String) -> URL? {
        guard !uri.isEmpty else {
            return nil
        }

        if let url = URL(string: uri), url.scheme != nil {
            return url
        }

        return URL(fileURLWithPath: uri)
    }

    @discardableResult
    func load() -> Bool {
        guard let item = currentItem, let url = resolveURL(item.audioUri) else {
            return false
        }

        do {
            let audioSession: AVAudioSession = AVAudioSession.sharedInstance()

            // only when setting .playAndRecord an output to earpiece is possible
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])

            // only try to override earpiece/speaker if selected output port
            // is builtInSpeaker/Receiver otherwise do nothing, e.g., in the case of airpods
            let portType = audioSession.currentRoute.outputs.first?.portType
            if portType == .builtInSpeaker || portType == .builtInReceiver {
                try audioSession.overrideOutputAudioPort(
                    earpiece ? AVAudioSession.PortOverride.none : AVAudioSession.PortOverride.speaker
                )
            }

            // set active as last
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.delegate = self

            initLockScreen()

            return true
        } catch {
            if !earpiece {
                earpiece = true
                return self.load()
            }
        }

        return false
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil

        // remove player from lock screen
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func play() {
        if audioPlayer?.isPlaying == false {
            audioPlayer?.play()
            updateLockScreen()
        }
    }

    func pause() {
        if audioPlayer?.isPlaying == true {
            audioPlayer?.pause()
            updateLockScreen()
        }
    }

    func select(_ id: String) -> Bool {
        // an id nothing carries leaves the playlist where it was, so the caller is told rather
        // than handed back the item it already had -- see select() in definitions.ts
        guard let index = playerItems.firstIndex(where: { $0.id == id }) else {
            return false
        }

        pause()
        currentIndex = index

        return load()
    }

    func next() -> Bool {
        guard !playerItems.isEmpty else {
            return false
        }

        pause()

        if currentIndex < (playerItems.count - 1) {
            currentIndex += 1
        } else {
            currentIndex = 0
        }

        return load()
    }

    func previous() -> Bool {
        guard !playerItems.isEmpty else {
            return false
        }

        pause()

        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            currentIndex = playerItems.count - 1
        }

        return load()
    }

    func seekTo(_ position: Int) {
        // a position outside the item is pulled to the nearest end of it. AVAudioPlayer does not
        // keep one that is out of range, so without this a seek past the end silently lands
        // wherever the player felt like rather than on the last moment of the audio.
        audioPlayer?.currentTime = Double(min(max(0, position), duration))
        updateLockScreen()
    }

    func setEarpiece() {
        let oldPosition = position
        pause()
        earpiece = true
        load()
        seekTo(oldPosition)
        notifyAudioOutputChange()
    }

    func setSpeaker() {
        let oldPosition = position
        pause()
        earpiece = false
        load()
        seekTo(oldPosition)
        notifyAudioOutputChange()
    }

    func initLockScreen(_ position: Int = 0) {
        guard let item = currentItem else {
            return
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: self.title,
            MPMediaItemPropertyArtist: self.subtitle,
            MPMediaItemPropertyPlaybackDuration: self.duration,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            // what the system would otherwise have to guess at: audio with a timeline,
            // rather than something it can only start and stop
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]

        // decode up front: the artwork request handler is invoked by the system on
        // an arbitrary thread, where a missing or corrupt image used to crash
        if let imageURL = resolveURL(item.imageUri), let image = UIImage(contentsOfFile: imageURL.path) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    /// Writes back the two fields the system cannot work out for itself, leaving the metadata
    /// and the decoded artwork alone.
    ///
    /// Every transition that changes where or whether the audio is playing has to go through
    /// here. The system only re-reads these when they are set, so anything that moves the
    /// player without setting them leaves the lock screen running a clock of its own.
    func updateLockScreen() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return
        }

        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            // an item that played out has to be ready to play again, rather than parked at its
            // end where play() would have nothing left to play -- see AudioPlayerState in
            // definitions.ts. This also puts the lock screen back to the start of the item.
            seekTo(0)
            onCompleted?(self.currentId)
        }
    }

}
