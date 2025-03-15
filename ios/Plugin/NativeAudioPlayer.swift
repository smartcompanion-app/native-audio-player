import Foundation
import AVFoundation
import Capacitor
import MediaPlayer

@objc public class NativeAudioPlayer: NSObject, AVAudioPlayerDelegate {
    
    var playerItems: [AudioPlayerItem] = []
    var audioPlayer: AVAudioPlayer?
    var currentIndex: Int = 0
    var earpiece: Bool = true
    var currentId: String {
        get {
            return playerItems[currentIndex].id
        }
    }
    var duration: Int {
        get {
            return Int(audioPlayer?.duration ?? 0)
        }
    }
    var position: Int {
        get {
            return Int(audioPlayer?.currentTime ?? 0)
        }
    }
    var title: String {
        get {
            return playerItems[currentIndex].title
        }
    }
    var subtitle: String {
        get {
            return playerItems[currentIndex].subtitle
        }
    }
    var onCompleted: ((_ id: String) -> Void)?
                
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
    
    func load() -> Bool {
        do {
            let audioSession : AVAudioSession = AVAudioSession.sharedInstance()
            
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
            
            // set active as last
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                                    
            //audioSession.currentRoute.outputs.forEach { print($0) }
                        
            if audioPlayer != nil {
                audioPlayer?.stop()
                audioPlayer = nil
            }
            
            let url = URL(fileURLWithPath: playerItems[currentIndex].audioUri)
            guard let dir = FileManager.default.urls(for: FileManager.SearchPathDirectory.documentDirectory, in: .userDomainMask).first else {
                return false
            }
            audioPlayer = try AVAudioPlayer(contentsOf: dir.appendingPathComponent(url.lastPathComponent))
            audioPlayer?.prepareToPlay()
            audioPlayer?.delegate = self
            
            initLockScreen()
            
            return true
        } catch {
            if !earpiece {
                earpiece = true
                return self.load()
            }
        }
        
        return false
    }
    
    func stop() {
        if audioPlayer != nil {
            audioPlayer?.stop()
            audioPlayer = nil
        }
        
        // remove player from lock screen
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    func play() {
        if let playing = audioPlayer?.isPlaying {
            if !playing {
                audioPlayer?.play()
                initLockScreen(self.position)
            }
        }
    }
    
    func pause() {
        if let playing = audioPlayer?.isPlaying {
            if playing {
                audioPlayer?.pause()
            }
        }
    }
    
    func select(_ id: String) -> Bool {
        pause()
        
        for (i, _) in playerItems.enumerated() {
            if playerItems[i].id == id {
                currentIndex = i
                break
            }
        }
        
        return load()
    }
    
    func next() -> Bool {
        pause()
        
        if currentIndex < (playerItems.count - 1) {
            currentIndex += 1
        } else {
            currentIndex = 0
        }
        
        return load()
    }
    
    func previous() -> Bool {
        pause()
        
        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            currentIndex = playerItems.count - 1
        }
        
        return load()
    }
    
    func seekTo(_ position: Int) {
        if audioPlayer != nil {
            //pause()
            audioPlayer?.currentTime = Double(position)
        }
    }
    
    func setEarpiece() {
        let oldPosition = position
        pause()
        earpiece = true
        load()
        seekTo(oldPosition)
    }
    
    func setSpeaker() {
        let oldPosition = position
        pause()
        earpiece = false
        load()
        seekTo(oldPosition)
    }
    
    func initLockScreen(_ position: Int = 0) {
        guard let dir = FileManager.default.urls(for: FileManager.SearchPathDirectory.documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let url = URL(fileURLWithPath: self.playerItems[self.currentIndex].imageUri)
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: self.title,
            MPMediaItemPropertyArtist: self.subtitle,
            MPMediaItemPropertyPlaybackDuration: self.duration,
            MPMediaItemPropertyArtwork: MPMediaItemArtwork(boundsSize: CGSize(width: 500, height: 500), requestHandler: { (size) -> UIImage in
                let uri = dir.appendingPathComponent(url.lastPathComponent).path
                return UIImage(contentsOfFile: uri)!
            }),
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position
        ]
    }
    
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if (flag) {            
            onCompleted?(self.currentId)
        }
    }
    
}
