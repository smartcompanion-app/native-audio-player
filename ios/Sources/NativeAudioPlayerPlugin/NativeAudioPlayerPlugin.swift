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
        CAPPluginMethod(name: "setEarpiece", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setSpeaker", returnType: CAPPluginReturnPromise)
    ]

    private var player: NativeAudioPlayer = NativeAudioPlayer([])
    
    private var pauseTarget: Any?
    private var playTarget: Any?
    private var nextTarget: Any?
    private var previousTarget: Any?
    private var seekTarget: Any?
        
    @objc func start(_ call: CAPPluginCall) {
        let items = call.getArray("items", [String: Any].self) ?? []
        player = NativeAudioPlayer(items)
        player.onCompleted = self.onCompleted
        
        if player.load() {
            let commandCenter = MPRemoteCommandCenter.shared()
                
            commandCenter.pauseCommand.isEnabled = true
            commandCenter.pauseCommand.removeTarget(pauseTarget)
            pauseTarget = commandCenter.pauseCommand.addTarget { event in
                self.onPause()
                return .success
            }
            
            commandCenter.playCommand.isEnabled = true
            commandCenter.playCommand.removeTarget(playTarget)
            playTarget = commandCenter.playCommand.addTarget { event in
                self.onPlay()
                return .success
            }
                        
            commandCenter.nextTrackCommand.isEnabled = true
            commandCenter.nextTrackCommand.removeTarget(nextTarget)
            nextTarget = commandCenter.nextTrackCommand.addTarget { event in
                self.onNext()
                return .success
            }
            
            commandCenter.previousTrackCommand.isEnabled = true
            commandCenter.previousTrackCommand.removeTarget(previousTarget)
            previousTarget = commandCenter.previousTrackCommand.addTarget { event in
                self.onPrevious()
                return .success
            }
            
            commandCenter.changePlaybackPositionCommand.isEnabled = true
            commandCenter.changePlaybackPositionCommand.removeTarget(seekTarget)
            seekTarget = commandCenter.changePlaybackPositionCommand.addTarget { event in
                if let changePlaybackPositionCommandEvent = event as? MPChangePlaybackPositionCommandEvent {
                    let positionTime = changePlaybackPositionCommandEvent.positionTime
                    self.player.seekTo(Int(positionTime))
                }
                return .success
            }
                                                
            call.resolve([
                "id": player.currentId
            ])
        } else {
            call.reject("could not load audio items")
        }
    }
    
    @objc func stop(_ call: CAPPluginCall) {
        onPause()
        player.stop()
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
            self.notifyListeners("update", data: ["id": player.currentId, "state": "skip"])
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
        //self.notifyListeners("update", data: ["id": player.currentId, "state": "paused"])
        player.seekTo(position)
        call.resolve()
    }
    
    @objc func getPosition(_ call: CAPPluginCall) {
        call.resolve(["value": player.position])
    }
    
    @objc func getDuration(_ call: CAPPluginCall) {
        call.resolve(["value": player.duration])
    }
    
    @objc func setEarpiece(_ call: CAPPluginCall) {
        self.notifyListeners("update", data: ["id": player.currentId, "state": "paused"])
        player.setEarpiece()
        call.resolve()
    }
        
    @objc func setSpeaker(_ call: CAPPluginCall) {
        self.notifyListeners("update", data: ["id": player.currentId, "state": "paused"])
        player.setSpeaker()
        call.resolve()
    }
    
    private func onPlay() {
        player.play()
        self.notifyListeners("update", data: ["id": player.currentId, "state": "playing"])
    }
    
    private func onPause() {
        
        player.pause()
        self.notifyListeners("update", data: ["id": player.currentId, "state": "paused"])
    }
    
    private func onNext() -> Bool {
        if player.next() {
            self.notifyListeners("update", data: ["id": player.currentId, "state": "skip"])
            return true
        } else {
            return false
        }
    }
    
    private func onPrevious() -> Bool {
        if player.previous() {
            self.notifyListeners("update", data: ["id": player.currentId, "state": "skip"])
            return true
        } else {
            return false
        }
    }
    
    private func onCompleted(_ id: String) {
        self.notifyListeners("update", data: ["id": id, "state": "completed"])
    }
    
}
