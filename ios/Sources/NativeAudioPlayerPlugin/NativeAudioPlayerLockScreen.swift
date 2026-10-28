import Foundation
import MediaPlayer
import UIKit

/// What the lock screen and control centre show for the player. Kept apart from the player
/// itself: it is written to a process-wide info center rather than to the audio.
extension NativeAudioPlayer {

    func initLockScreen(_ position: Int = 0) {
        guard let item = currentItem else {
            return
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: self.title,
            MPMediaItemPropertyArtist: self.subtitle,
            MPMediaItemPropertyPlaybackDuration: self.duration,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
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
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(rate)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
