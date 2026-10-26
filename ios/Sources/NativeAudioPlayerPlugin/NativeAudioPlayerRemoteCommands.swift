import Foundation
import Capacitor
import MediaPlayer

/// The plumbing behind the lock screen and control centre transport. Kept apart from the
/// plugin methods in NativeAudioPlayerPlugin.swift: these talk to a process-wide singleton
/// rather than to a call.
extension NativeAudioPlayerPlugin {

    /// Hands the lock screen and control centre transport to the player that was just loaded.
    func installRemoteCommandTargets() {
        let commandCenter = MPRemoteCommandCenter.shared()

        disableUnhandledCommands()

        setTarget(commandCenter.pauseCommand, &pauseTarget) { [weak self] _ in
            self?.onPause()
            return .success
        }

        setTarget(commandCenter.playCommand, &playTarget) { [weak self] _ in
            self?.onPlay()
            return .success
        }

        // what a headset or bluetooth button sends: one command for both directions,
        // rather than the separate play and pause the on-screen controls use
        setTarget(commandCenter.togglePlayPauseCommand, &toggleTarget) { [weak self] _ in
            self?.onTogglePlayPause()
            return .success
        }

        setTarget(commandCenter.nextTrackCommand, &nextTarget) { [weak self] _ in
            self?.onNext()
            return .success
        }

        setTarget(commandCenter.previousTrackCommand, &previousTarget) { [weak self] _ in
            self?.onPrevious()
            return .success
        }

        setTarget(commandCenter.changePlaybackPositionCommand, &seekTarget) { [weak self] event in
            if let changePlaybackPositionCommandEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.onSeekTo(changePlaybackPositionCommandEvent.positionTime)
            }
            return .success
        }
    }

    /// Turns off every command the plugin does not answer.
    ///
    /// MPRemoteCommandCenter is a process-wide singleton on which every command starts out
    /// enabled, so leaving one alone is not the same as not offering it: it is a control the
    /// system is willing to draw and nothing will ever respond to. The skip pair is the one
    /// that costs. While those are enabled the transport shows the fifteen-second skip
    /// buttons in place of the track buttons, which is why next and previous could be
    /// registered and enabled and still never reach the app.
    func disableUnhandledCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        let unhandled: [MPRemoteCommand] = [
            commandCenter.skipForwardCommand,
            commandCenter.skipBackwardCommand,
            commandCenter.seekForwardCommand,
            commandCenter.seekBackwardCommand,
            commandCenter.stopCommand,
            commandCenter.changePlaybackRateCommand,
            commandCenter.changeRepeatModeCommand,
            commandCenter.changeShuffleModeCommand,
            commandCenter.likeCommand,
            commandCenter.dislikeCommand,
            commandCenter.bookmarkCommand,
            commandCenter.ratingCommand,
            commandCenter.enableLanguageOptionCommand,
            commandCenter.disableLanguageOptionCommand
        ]

        for command in unhandled {
            command.isEnabled = false
        }
    }

    func setTarget(
        _ command: MPRemoteCommand,
        _ existing: inout Any?,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true

        // removeTarget(nil) drops *every* target registered for the command,
        // including ones belonging to the host app or another plugin
        if let existing {
            command.removeTarget(existing)
        }

        existing = command.addTarget(handler: handler)
    }

    func removeRemoteCommandTargets() {
        let commandCenter = MPRemoteCommandCenter.shared()
        let registered: [(MPRemoteCommand, Any?)] = [
            (commandCenter.pauseCommand, pauseTarget),
            (commandCenter.playCommand, playTarget),
            (commandCenter.togglePlayPauseCommand, toggleTarget),
            (commandCenter.nextTrackCommand, nextTarget),
            (commandCenter.previousTrackCommand, previousTarget),
            (commandCenter.changePlaybackPositionCommand, seekTarget)
        ]

        for (command, target) in registered {
            if let target {
                command.removeTarget(target)
            }
        }

        pauseTarget = nil
        playTarget = nil
        toggleTarget = nil
        nextTarget = nil
        previousTarget = nil
        seekTarget = nil
    }

    func onPlay() {
        player.play()
        self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "playing"])
    }

    func onPause() {
        player.pause()
        self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "paused"])
    }

    /// Answers the single button a headset offers, which has to work out for itself
    /// which direction it means.
    func onTogglePlayPause() {
        if player.isPlaying {
            onPause()
        } else {
            onPlay()
        }
    }

    /// Moves on and reports the skip once the item has loaded. A load that another overtook is
    /// not reported at all, so pressing next twice in a row reports one skip, for the item it
    /// ends on.
    func onNext(_ completion: @escaping (Bool) -> Void = { _ in }) {
        player.next { [weak self] loaded in
            self?.onSkipped(loaded)
            completion(loaded)
        }
    }

    func onPrevious(_ completion: @escaping (Bool) -> Void = { _ in }) {
        player.previous { [weak self] loaded in
            self?.onSkipped(loaded)
            completion(loaded)
        }
    }

    private func onSkipped(_ loaded: Bool) {
        if loaded {
            self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "skipped"])
        }
    }

    /// Reports the playback the system stopped on the app's behalf.
    ///
    /// The player half of this is already done by the time it gets here, so this only announces
    /// it -- going through onPause() would pause a player that is not running and report a
    /// change that did not happen.
    func onInterrupted() {
        self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "paused"])
    }

    func onProgress() {
        self.notifyListeners("progress", data: [
            "id": player.currentId,
            "position": player.position,
            "duration": player.duration
        ])
    }

    func onCompleted(_ id: String) {
        self.notifyListeners("audioPlayerChange", data: ["id": id, "state": "completed"])
    }

    func onAudioOutputChanged(_ output: String) {
        self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "paused"])
        self.notifyListeners("audioOutputChange", data: ["output": output])
    }
}
