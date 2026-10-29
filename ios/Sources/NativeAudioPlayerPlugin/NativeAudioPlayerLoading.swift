import Foundation
import AVFoundation

/// Getting an item to the point where it can be played.
///
/// Asynchronous, unlike AVAudioPlayer was: an AVPlayerItem only knows whether it can be played --
/// and how long it is -- once its asset has been read, which for a remote item means once enough
/// of it has arrived. The completion answers that question, so a caller that resolves from it
/// hands back an item whose duration is already known, and rejects one that will never play.
extension NativeAudioPlayer {

    /// Loads the current item. The completion is called once, on the main queue: true once the
    /// item can be played, false when it cannot -- including when nothing is selected, the session
    /// cannot be configured, or another load or a stop() overtook this one before it settled.
    func load(_ completion: @escaping (Bool) -> Void = { _ in }) {
        // anything still loading is not what is wanted any more
        cancelLoad()
        loadGeneration += 1
        let generation = loadGeneration

        audioPlayer?.pause()
        playWhenReady = false
        pendingSeek = nil
        stopProgress()

        guard let item = currentItem, let url = resolveURL(item.audioUri) else {
            completion(false)
            return
        }

        do {
            try configureSession()
        } catch {
            // No retry on the other output. The one that used to be here ran whenever the
            // player was on the speaker, which was the state setSpeaker() opted into and is
            // now the default -- so every failed load flipped the player to the earpiece and
            // left it there, and the next item that did load played out of it. A load that
            // failed reports that it failed, and leaves the configured output alone.
            completion(false)
            return
        }

        let playerItem = AVPlayerItem(url: url)
        // keeps the pitch whatever the rate -- only varispeed lets it move with it -- and the
        // spectral one is the algorithm that still sounds like speech at either end of the range
        playerItem.audioTimePitchAlgorithm = .spectral

        let player = audioPlayer ?? makePlayer()
        audioPlayer = player
        observeEnd(of: playerItem)
        player.replaceCurrentItem(with: playerItem)

        pendingLoadCompletion = completion
        statusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            let status = observed.status

            DispatchQueue.main.async {
                guard let self, generation == self.loadGeneration else {
                    return
                }

                switch status {
                case .readyToPlay:
                    // the duration is known from here on, which is what the lock screen needs
                    self.initLockScreen()
                    self.finishLoad(true)
                case .failed:
                    self.finishLoad(false)
                default:
                    break
                }
            }
        }
    }

    /// Answers a load that is still under way with false and stops listening for its outcome.
    func cancelLoad() {
        statusObservation = nil
        finishLoad(false)
    }

    private func finishLoad(_ loaded: Bool) {
        statusObservation = nil

        let completion = pendingLoadCompletion
        pendingLoadCompletion = nil
        completion?(loaded)
    }

    private func makePlayer() -> AVPlayer {
        let player = AVPlayer()
        // stop at the end of an item rather than doing anything else -- the plugin never
        // advances on its own, see AudioPlayerState in definitions.ts
        player.actionAtItemEnd = .pause
        return player
    }

    /// Follows the end of this one item, and of no other: a notification from an item that has
    /// since been replaced is about audio that is no longer playing.
    private func observeEnd(of playerItem: AVPlayerItem) {
        NotificationCenter.default.removeObserver(self, name: AVPlayerItem.didPlayToEndTimeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemEnd),
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: playerItem
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemFailure),
            name: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: playerItem
        )
    }

    // posted on whichever thread the player was on, and everything else here runs on main

    @objc private func handleItemEnd(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, notification.object as? AVPlayerItem === self.audioPlayer?.currentItem else {
                return
            }

            self.itemDidPlayToEnd()
        }
    }

    @objc private func handleItemFailure(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, notification.object as? AVPlayerItem === self.audioPlayer?.currentItem else {
                return
            }

            self.itemFailedToPlayToEnd()
        }
    }
}
