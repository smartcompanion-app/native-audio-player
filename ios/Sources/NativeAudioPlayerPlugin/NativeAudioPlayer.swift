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
    var title: String {
        currentItem?.title ?? ""
    }
    var subtitle: String {
        currentItem?.subtitle ?? ""
    }
    var onCompleted: ((_ id: String) -> Void)?

    /// `didPause` reports whether the output change stopped playback, so the plugin only
    /// announces a pause that actually happened.
    var onAudioOutputChanged: ((_ output: String, _ didPause: Bool) -> Void)?

    /// The output the session is routed to right now, which is not necessarily the one that
    /// was requested: the earpiece/speaker override is skipped while an external device is
    /// connected, see `load()`.
    var audioOutput: String {
        NativeAudioPlayer.audioOutput(for: AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType)
    }

    /// The last output handed to `onAudioOutputChanged`, so route changes that leave the
    /// output as it was -- switching between two bluetooth devices, say -- stay silent.
    /// Not private so the tests can seed a route the host machine does not have.
    var notifiedAudioOutput: String?

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
        notifiedAudioOutput = audioOutput

        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        notifyAudioOutputChange()
    }

    func notifyAudioOutputChange() {
        let output = audioOutput

        if output != notifiedAudioOutput {
            notifiedAudioOutput = output

            // audio that was going to the earpiece must not carry on out loud once the route
            // changed, so playback stops on every output change and the app decides whether to
            // resume. setEarpiece/setSpeaker have already paused by the time they get here, so
            // this only reports a pause for the route changes the plugin did not cause.
            let didPause = audioPlayer?.isPlaying == true
            if didPause {
                pause()
            }

            onAudioOutputChanged?(output, didPause)
        }
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
            initLockScreen(self.position)
        }
    }

    func pause() {
        if audioPlayer?.isPlaying == true {
            audioPlayer?.pause()
        }
    }

    func select(_ id: String) -> Bool {
        guard !playerItems.isEmpty else {
            return false
        }

        pause()

        if let index = playerItems.firstIndex(where: { $0.id == id }) {
            currentIndex = index
        }

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
        audioPlayer?.currentTime = Double(position)
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
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position
        ]

        // decode up front: the artwork request handler is invoked by the system on
        // an arbitrary thread, where a missing or corrupt image used to crash
        if let imageURL = resolveURL(item.imageUri), let image = UIImage(contentsOfFile: imageURL.path) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            onCompleted?(self.currentId)
        }
    }

}
