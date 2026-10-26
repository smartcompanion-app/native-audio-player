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
        CAPPluginMethod(name: "getState", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAudioOutput", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEarpiece", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setSpeaker", returnType: CAPPluginReturnPromise)
    ]

    // not private: the remote command plumbing in NativeAudioPlayerRemoteCommands.swift drives it too
    var player: NativeAudioPlayer = NativeAudioPlayer([])

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
        player.progressInterval = NativeAudioPlayer.progressInterval(for: call.getDouble("progressInterval"))
        player.onProgress = { [weak self] in
            self?.onProgress()
        }
        player.onCompleted = { [weak self] id in
            self?.onCompleted(id)
        }
        player.onAudioOutputChanged = { [weak self] output in
            self?.onAudioOutputChanged(output)
        }
        player.onInterrupted = { [weak self] in
            self?.onInterrupted()
        }

        if player.load() {
            player.observeAudioOutput()
            player.observeInterruptions()

            installRemoteCommandTargets()

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
        // reported whatever was happening, since clearing the playlist is a change either way --
        // and as the one stopped, rather than a paused for the playback it ends as well
        self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "stopped"])
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

        // Pausing a player that is not running changes nothing, and a state is reported per
        // change rather than per call -- see AudioPlayerState in definitions.ts. An app that
        // pauses while a slider is dragged calls this on every input event, which is many
        // times over one gesture, and only the first of them stops anything.
        //
        // stop() reports stopped whatever was happening, since clearing the playlist is a
        // change either way, and so it does not come through here.
        if player.audioPlayer?.isPlaying == true {
            onPause()
        }

        call.resolve()
    }

    @objc func select(_ call: CAPPluginCall) {
        let id = call.getString("id") ?? ""

        if player.select(id) {
            self.notifyListeners("audioPlayerChange", data: ["id": player.currentId, "state": "skipped"])
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

        onSeekTo(call.getDouble("position") ?? 0)

        call.resolve()
    }

    /// Moves the player and starts it, which is what seeking means for every caller -- see
    /// seekTo in the behaviour overview in the README.
    ///
    /// Not private, and not inlined into either caller: the lock screen scrubber reaches this
    /// through a command handler rather than through seekTo above, and while it did the work
    /// itself it dropped the resume and the playing event that the contract promises.
    func onSeekTo(_ position: TimeInterval) {
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

    /// Nothing loaded is an answer rather than a failure, see getState in definitions.ts. The
    /// playlist outlives stop() on the player, so it is the missing audio player that says
    /// nothing is loaded -- currentId would still name the item that was.
    @objc func getState(_ call: CAPPluginCall) {
        guard let audioPlayer = player.audioPlayer else {
            call.resolve(["id": "", "state": "stopped", "position": 0.0, "duration": 0.0])
            return
        }

        call.resolve([
            "id": player.currentId,
            "state": audioPlayer.isPlaying ? "playing" : "paused",
            "position": player.position,
            "duration": player.duration
        ])
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
