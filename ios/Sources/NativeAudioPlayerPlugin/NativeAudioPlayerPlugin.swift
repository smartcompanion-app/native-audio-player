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
        player.onAudioOutputChanged = { [weak self] output, didPause in
            self?.onAudioOutputChanged(output, didPause)
        }

        if player.load() {
            player.observeAudioOutput()

            let commandCenter = MPRemoteCommandCenter.shared()

            setTarget(commandCenter.pauseCommand, &pauseTarget) { [weak self] _ in
                self?.onPause()
                return .success
            }

            setTarget(commandCenter.playCommand, &playTarget) { [weak self] _ in
                self?.onPlay()
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
                    self?.player.seekTo(Int(positionTime))
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
        onPlay()
        call.resolve()
    }

    @objc func pause(_ call: CAPPluginCall) {
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
        let position = call.getInt("position") ?? 0
        player.seekTo(position)
        call.resolve()
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
        // switching the output reloads the player, which leaves it paused
        self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "paused"])
        player.setEarpiece()
        call.resolve()
    }

    @objc func setSpeaker(_ call: CAPPluginCall) {
        self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "paused"])
        player.setSpeaker()
        call.resolve()
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

    private func onAudioOutputChanged(_ output: String, _ didPause: Bool) {
        if didPause {
            self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "paused"])
        }

        self.notifyListeners("audioOutputChange", data: ["output": output])
    }

}
