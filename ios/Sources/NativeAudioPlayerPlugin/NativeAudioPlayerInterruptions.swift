import Foundation
import AVFoundation

/// Playback the system stops on the app's behalf: an incoming call, Siri, or another app taking
/// the audio session.
///
/// Kept apart from the player itself: none of this is a transition anybody asked for, and the
/// session has to be put back together afterwards before the player can be used again.
extension NativeAudioPlayer {

    /// Starts reporting interruptions. Removes before adding, the way `observeAudioOutput` does,
    /// so a second `start()` cannot register the same observer twice.
    func observeInterruptions() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            interruptionBegan()
        case .ended:
            // the interruption deactivated the session and play() does not activate one, so
            // without this the next play() moves the playhead in silence. The .shouldResume
            // hint is deliberately ignored: playback is not resumed on its own, see
            // AudioPlayerState in definitions.ts.
            try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        @unknown default:
            break
        }
    }

    private func interruptionBegan() {
        // the system has already stopped the player, so isPlaying cannot say whether this
        // interrupted anything -- playWhenReady is what was actually asked for
        let wasPlaying = playWhenReady

        audioPlayer?.pause()
        playWhenReady = false

        // explicitly, rather than through pause(): its guard is on isPlaying, which the system
        // has already cleared, so the lock screen would keep a rate of 1.0 and go on offering
        // pause for audio that is not running
        updateLockScreen()

        if wasPlaying {
            onInterrupted?()
        }
    }
}
