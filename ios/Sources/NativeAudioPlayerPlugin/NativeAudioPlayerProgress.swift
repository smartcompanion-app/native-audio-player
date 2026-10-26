import Foundation

/// The ticks behind the progress event, which reports the playhead while the audio runs -- see the
/// progress event in definitions.ts.
///
/// On the main queue rather than a run loop timer: the plugin methods that start playback run on
/// Capacitor's own queue, which has no run loop to fire a Timer on.
extension NativeAudioPlayer {

    static let defaultProgressInterval: TimeInterval = 0.5

    /// What an interval start() was given turns into: anything that is not a positive number
    /// falls back to the default -- see StartOptions.progressInterval in definitions.ts.
    static func progressInterval(for seconds: Double?) -> TimeInterval {
        guard let seconds, seconds > 0 else {
            return defaultProgressInterval
        }

        return seconds
    }

    /// Reports the playhead every interval for as long as the audio runs. A tick that finds the
    /// player stopped ends the reporting itself, so a stop that never came through pause() --
    /// the system stopping the player, say -- cannot leave it running.
    func startProgress() {
        // restarted rather than added to: play() can come round again inside one interval
        stopProgress()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + progressInterval, repeating: progressInterval)
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            if self.isPlaying {
                self.onProgress?()
            } else {
                self.stopProgress()
            }
        }
        timer.resume()
        progressTimer = timer
    }

    func stopProgress() {
        progressTimer?.cancel()
        progressTimer = nil
    }
}
