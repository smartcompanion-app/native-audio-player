import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@objc public class NativeAudioPlayer: NSObject {

    var playerItems: [AudioPlayerItem] = []
    var currentIndex: Int = 0

    /// The player for the current item, or nil while nothing is loaded -- before the first load
    /// and after stop(). One player is kept across items, which are swapped in by load().
    ///
    /// AVPlayer rather than AVAudioPlayer: AVAudioPlayer only reads files that are already on the
    /// device, while AVPlayer streams a remote URL as readily as it plays a local one -- see
    /// Item.audioUri in definitions.ts.
    var audioPlayer: AVPlayer?

    /// Whether the built-in output is overridden to the earpiece rather than the speaker.
    ///
    /// The speaker is the default, as it is on Android: audio a listener has not asked to keep
    /// private should be audible without holding the phone to an ear. The earpiece is what
    /// `setEarpiece()` opts into.
    var earpiece: Bool = false

    /// Whether playback was asked for, which is not the same as whether it is happening.
    ///
    /// The system stops the player before it delivers an interruption, so `isPlaying` reads
    /// false by the time the notification arrives and cannot say whether anything was actually
    /// interrupted. This is the answer to that question, and nothing else should be read for it.
    var playWhenReady: Bool = false

    /// The speed the audio plays at, see setRate in definitions.ts. AVPlayer plays at whatever
    /// rate it is started with, so play() is where this reaches it.
    var rate: Float = 1.0

    // MARK: Loading -- see NativeAudioPlayerLoading.swift

    /// Counts loads, so the outcome of one that a later load overtook is not taken for the
    /// outcome of the item that is current now.
    var loadGeneration = 0

    /// Answers the load that is under way. Held here rather than only in the status observer, so
    /// a load that is overtaken -- or stopped -- before its item settled is still answered.
    var pendingLoadCompletion: ((Bool) -> Void)?

    var statusObservation: NSKeyValueObservation?

    /// Where a seek is headed while it is under way. AVPlayer seeks asynchronously, and reading
    /// the time before it lands reports where the player was rather than where it was sent.
    var pendingSeek: TimeInterval?

    // the item currentIndex points at, or nil while the playlist is empty --
    // everything below reads through this so an unset playlist cannot trap
    var currentItem: AudioPlayerItem? {
        playerItems.indices.contains(currentIndex) ? playerItems[currentIndex] : nil
    }
    var currentId: String {
        currentItem?.id ?? ""
    }

    /// Whether the audio is running, or about to: a player that was asked to play and is waiting
    /// for a stream to buffer counts as playing, the way AVAudioPlayer's isPlaying did the moment
    /// play() was called. A rate of 0 is the only thing that means stopped.
    var isPlaying: Bool {
        (audioPlayer?.rate ?? 0) != 0
    }
    var duration: TimeInterval {
        NativeAudioPlayer.seconds(audioPlayer?.currentItem?.duration)
    }
    var position: TimeInterval {
        pendingSeek ?? NativeAudioPlayer.seconds(audioPlayer?.currentTime())
    }

    /// A time as seconds, or 0 for one that is not a number of seconds yet: an item whose
    /// duration is not known reports it as indefinite, and so does a live stream.
    static func seconds(_ time: CMTime?) -> TimeInterval {
        guard let time, time.isNumeric else {
            return 0
        }

        return time.seconds.isFinite ? max(0, time.seconds) : 0
    }

    /// What the lock screen is told about the speed of playback.
    ///
    /// It is not decoration: the system runs its own clock from the elapsed time it was last
    /// given, advancing it at this rate, and draws the transport button from it -- a non-zero
    /// rate means playing, so it offers pause. A rate left at 1.0 on a paused player therefore
    /// keeps offering pause, and the play command can never be reached from the lock screen.
    var playbackRate: Double {
        isPlaying ? Double(rate) : 0.0
    }
    var title: String {
        currentItem?.title ?? ""
    }
    var subtitle: String {
        currentItem?.subtitle ?? ""
    }
    var onCompleted: ((_ id: String) -> Void)?

    var onAudioOutputChanged: ((_ output: String) -> Void)?

    /// Called when something outside the app stopped playback that was running -- an incoming
    /// call, Siri, another app taking the audio session, or a stream that broke off.
    var onInterrupted: (() -> Void)?

    /// Called every `progressInterval` seconds while the audio runs, see the progress event in
    /// definitions.ts.
    var onProgress: (() -> Void)?

    /// How often `onProgress` is called, in seconds. Set before playback starts; a running timer
    /// keeps the interval it was started with.
    var progressInterval: TimeInterval = NativeAudioPlayer.defaultProgressInterval

    /// Driven from NativeAudioPlayerProgress.swift, which is why it is not private.
    var progressTimer: DispatchSourceTimer?

    /// The output the session is routed to right now, which is not necessarily the one that
    /// was requested: the earpiece/speaker override is skipped while an external device is
    /// connected, see `configureSession()`.
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
        stopProgress()

        // only tear down when this instance still owns a player: an instance that
        // never loaded must not deactivate the session or clear the lock screen
        // that a different instance has since taken over
        if audioPlayer != nil {
            stop()
        } else {
            pendingLoadCompletion?(false)
            pendingLoadCompletion = nil
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
        // Only a device the user connected or disconnected is an output change. Configuring the
        // session sets the category and the port override, and both raise this notification as
        // well -- acting on those would have start(), next() and select() pause the playback
        // they just prepared.
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
    // A URL with any other scheme, http(s) above all, is taken as it is.
    func resolveURL(_ uri: String) -> URL? {
        guard !uri.isEmpty else {
            return nil
        }

        if let url = URL(string: uri), url.scheme != nil {
            return url
        }

        return URL(fileURLWithPath: uri)
    }

    /// Puts the session into the shape playback needs: a category that can reach the earpiece,
    /// the earpiece or speaker override, and active.
    func configureSession() throws {
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

        // set active as last. No options: .notifyOthersOnDeactivation is what its name says,
        // and only means anything when deactivating -- see stop().
        try audioSession.setActive(true)
    }

    func stop() {
        cancelLoad()
        audioPlayer?.pause()
        audioPlayer?.replaceCurrentItem(with: nil)
        audioPlayer = nil
        playWhenReady = false
        pendingSeek = nil
        stopProgress()

        // remove player from lock screen
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func play() {
        guard let audioPlayer, !isPlaying else {
            return
        }

        // the session is activated when an item loads, but it can have been deactivated since:
        // an interruption does that, and the reactivation when it ends fails while the app that
        // interrupted still holds the session. Playing on an inactive session is silent rather
        // than a failure anything reports. Activating an active session costs nothing, so this
        // asks every time rather than trying to work out when it matters.
        try? AVAudioSession.sharedInstance().setActive(true)

        playWhenReady = true
        // setting the rate is what starts an AVPlayer, at that rate
        audioPlayer.rate = rate
        updateLockScreen()
        startProgress()
    }

    func pause() {
        // outside the guard: a player the system already stopped is still one nobody is asking
        // to play, and leaving this set would have the next interruption report a pause that
        // interrupted nothing
        playWhenReady = false
        stopProgress()

        if isPlaying {
            audioPlayer?.pause()
            updateLockScreen()
        }
    }

    func seekTo(_ position: TimeInterval) {
        guard let audioPlayer else {
            return
        }

        // a position outside the item is pulled to the nearest end of it, so a seek past the end
        // lands on the last moment of the audio rather than wherever the player felt like
        let target = min(max(0, position), duration)
        pendingSeek = target

        // exactly there rather than on a nearby keyframe: a scrubber that hands back a position
        // getPosition() reported expects to find the audio where it left it
        audioPlayer.seek(
            to: CMTime(seconds: target, preferredTimescale: 1000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            DispatchQueue.main.async {
                // a later seek has taken over, and its target is the one to report
                guard let self, self.pendingSeek == target else {
                    return
                }

                self.pendingSeek = nil
                self.updateLockScreen()
            }
        }

        updateLockScreen()
    }

    /// Changes the speed of whatever is loaded, playing or not, and of everything loaded after it.
    func setRate(_ value: Float) {
        rate = value

        // a paused AVPlayer would start if it were given a rate, so it is only handed one while
        // it is running -- play() hands it over otherwise
        if isPlaying {
            audioPlayer?.rate = value
        }

        updateLockScreen()
    }

    /// The override is a property of the session rather than of the player, so the item stays
    /// where it is and only the route moves.
    func setEarpiece() {
        pause()
        earpiece = true
        try? configureSession()
        notifyAudioOutputChange()
    }

    func setSpeaker() {
        pause()
        earpiece = false
        try? configureSession()
        notifyAudioOutputChange()
    }

    /// The item ran out.
    func itemDidPlayToEnd() {
        // nothing is asking for playback any more -- left set, the next interruption would
        // report a pause that interrupted nothing
        playWhenReady = false
        stopProgress()
        audioPlayer?.pause()

        // an item that played out has to be ready to play again, rather than parked at its
        // end where play() would have nothing left to play -- see AudioPlayerState in
        // definitions.ts. This also puts the lock screen back to the start of the item.
        seekTo(0)
        onCompleted?(self.currentId)
    }

    /// The item stopped before its end because it could not go on -- a stream that broke off,
    /// say. Nothing completed, so the position stays where the audio stopped, and the stop is
    /// reported the way an interruption is: playback ended without anybody asking.
    func itemFailedToPlayToEnd() {
        let wasPlaying = playWhenReady

        playWhenReady = false
        stopProgress()
        audioPlayer?.pause()
        updateLockScreen()

        if wasPlaying {
            onInterrupted?()
        }
    }
}
