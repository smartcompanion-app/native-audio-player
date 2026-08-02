import Foundation
import Capacitor
import MediaPlayer

@objc(NativeAudioPlayerPlugin)
public class NativeAudioPlayerPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "NativeAudioPlayerPlugin"
    public let jsName = "NativeAudioPlayer"

    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "play", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pause", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "select", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "next", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "previous", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "seekTo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPosition", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDuration", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAudioOutput", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEarpiece", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setSpeaker", returnType: CAPPluginReturnPromise)
    ]

    private var player: NativeAudioPlayer = NativeAudioPlayer([])

    // not private so the tests can tell an installed target from a removed one --
    // MPRemoteCommand exposes no way to read back what is registered on it
    var pauseTarget: Any?
    var playTarget: Any?
    var toggleTarget: Any?
    var nextTarget: Any?
    var previousTarget: Any?
    var seekTarget: Any?

    deinit {
        // MPRemoteCommandCenter is a process-wide singleton and holds its target
        // blocks for the lifetime of the app -- leaving them behind leaks the plugin
        removeRemoteCommandTargets()
    }

    @objc func start(_ call: CAPPluginCall) {
        let items = call.getArray("items", [String: Any].self) ?? []
        player = NativeAudioPlayer(items)
        player.onCompleted = { [weak self] id in
            self?.onCompleted(id)
        }
        player.onAudioOutputChanged = { [weak self] output in
            self?.onAudioOutputChanged(output)
        }

        if player.load() {
            player.observeAudioOutput()

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
                _ = self?.onNext()
                return .success
            }

            setTarget(commandCenter.previousTrackCommand, &previousTarget) { [weak self] _ in
                _ = self?.onPrevious()
                return .success
            }

            setTarget(commandCenter.changePlaybackPositionCommand, &seekTarget) { [weak self] event in
                if let changePlaybackPositionCommandEvent = event as? MPChangePlaybackPositionCommandEvent {
                    let positionTime = changePlaybackPositionCommandEvent.positionTime
                    self?.onSeekTo(Int(positionTime))
                }
                return .success
            }

            call.resolve([
                "id": player.currentId
            ])
        } else {
            // the player this start() replaced is gone, so its handlers must not stay
            // on the process-wide command center and drive a player nobody can reach
            removeRemoteCommandTargets()
            call.reject("could not load audio items")
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        onPause()
        player.stop()
        removeRemoteCommandTargets()
        call.resolve()
    }

    @objc func play(_ call: CAPPluginCall) {
        guard requireLoadedItem(call) else {
            return
        }

        onPlay()
        call.resolve()
    }

    /// Answers the call and reports false when nothing is loaded, which is the case before
    /// start() and after stop(). Acting then would only report playback that cannot happen --
    /// see the behaviour overview in the README.
    private func requireLoadedItem(_ call: CAPPluginCall) -> Bool {
        if player.audioPlayer == nil {
            call.reject("could not play without a loaded audio item")
            return false
        }

        return true
    }

    @objc func pause(_ call: CAPPluginCall) {
        guard requireLoadedItem(call) else {
            return
        }

        onPause()
        call.resolve()
    }

    @objc func select(_ call: CAPPluginCall) {
        let id = call.getString("id") ?? ""

        if player.select(id) {
            self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "skip"])
            call.resolve(["id": player.currentId])
        } else {
            call.reject("could not switch to item with given id")
        }
    }

    @objc func next(_ call: CAPPluginCall) {
        if onNext() {
            call.resolve(["id": player.currentId])
        } else {
            call.reject("could not switch to next item")
        }
    }

    @objc func previous(_ call: CAPPluginCall) {
        if onPrevious() {
            call.resolve(["id": player.currentId])
        } else {
            call.reject("could not switch to previous item")
        }
    }

    @objc func seekTo(_ call: CAPPluginCall) {
        guard requireLoadedItem(call) else {
            return
        }

        onSeekTo(call.getInt("position") ?? 0)

        call.resolve()
    }

    /// Moves the player and starts it, which is what seeking means for every caller -- see
    /// seekTo in the behaviour overview in the README.
    ///
    /// Not private, and not inlined into either caller: the lock screen scrubber reaches this
    /// through a command handler rather than through seekTo above, and while it did the work
    /// itself it dropped the resume and the playing event that the contract promises.
    func onSeekTo(_ position: Int) {
        let wasPlaying = player.audioPlayer?.isPlaying == true

        player.seekTo(position)

        // seeking resumes, so a listener dragged the scrubber and hears the audio carry on from
        // where they dropped it. Already playing is not a change, and reports nothing.
        if !wasPlaying {
            onPlay()
        }
    }

    @objc func getPosition(_ call: CAPPluginCall) {
        call.resolve(["value": player.position])
    }

    @objc func getDuration(_ call: CAPPluginCall) {
        call.resolve(["value": player.duration])
    }

    @objc func getAudioOutput(_ call: CAPPluginCall) {
        call.resolve(["output": player.audioOutput])
    }

    @objc func setEarpiece(_ call: CAPPluginCall) {
        guard requireLoadedItem(call) else {
            return
        }

        // switching the output reloads the player, which leaves it paused
        self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "paused"])
        player.setEarpiece()
        call.resolve()
    }

    @objc func setSpeaker(_ call: CAPPluginCall) {
        guard requireLoadedItem(call) else {
            return
        }

        self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "paused"])
        player.setSpeaker()
        call.resolve()
    }

}

/// The plumbing behind the lock screen and control centre transport. Kept apart from the
/// plugin methods above: these talk to a process-wide singleton rather than to a call.
extension NativeAudioPlayerPlugin {

    /// Turns off every command the plugin does not answer.
    ///
    /// MPRemoteCommandCenter is a process-wide singleton on which every command starts out
    /// enabled, so leaving one alone is not the same as not offering it: it is a control the
    /// system is willing to draw and nothing will ever respond to. The skip pair is the one
    /// that costs. While those are enabled the transport shows the fifteen-second skip
    /// buttons in place of the track buttons, which is why next and previous could be
    /// registered and enabled and still never reach the app.
    private func disableUnhandledCommands() {
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

    private func setTarget(
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

    private func removeRemoteCommandTargets() {
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

    private func onPlay() {
        player.play()
        self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "playing"])
    }

    private func onPause() {
        player.pause()
        self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "paused"])
    }

    /// Answers the single button a headset offers, which has to work out for itself
    /// which direction it means.
    private func onTogglePlayPause() {
        if player.audioPlayer?.isPlaying == true {
            onPause()
        } else {
            onPlay()
        }
    }

    private func onNext() -> Bool {
        if player.next() {
            self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "skip"])
            return true
        } else {
            return false
        }
    }

    private func onPrevious() -> Bool {
        if player.previous() {
            self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "skip"])
            return true
        } else {
            return false
        }
    }

    private func onCompleted(_ id: String) {
        self.notifyListeners("audioPlayerChange", data: ["id": id, "state": "completed"])
    }

    private func onAudioOutputChanged(_ output: String) {
        self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "paused"])
        self.notifyListeners("audioOutputChange", data: ["output": output])
    }
}
