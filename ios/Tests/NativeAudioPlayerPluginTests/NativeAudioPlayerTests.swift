import XCTest
import MediaPlayer
@testable import NativeAudioPlayerPlugin

class NativeAudioPlayerTests: PluginTestCase {

    private func makePlayer() -> NativeAudioPlayer {
        return NativeAudioPlayer([
            [
                "id": "1",
                "title": "Elephant",
                "subtitle": "Africa",
                "audioUri": "file:///elephant.mp3",
                "imageUri": "file:///elephant.jpg"
            ],
            [
                "id": "2",
                "title": "Leopard",
                "subtitle": "Asia",
                "audioUri": "file:///leopard.mp3",
                "imageUri": "file:///leopard.jpg"
            ],
            [
                "id": "3",
                "title": "Crocodile",
                "subtitle": "Australia",
                "audioUri": "file:///crocodile.mp3",
                "imageUri": "file:///crocodile.jpg"
            ]
        ])
    }

    func testInitMapsItemsAndStartsAtTheFirstOne() {
        let player = makePlayer()

        XCTAssertEqual(player.playerItems.count, 3)
        XCTAssertEqual(player.currentId, "1")
        XCTAssertEqual(player.title, "Elephant")
        XCTAssertEqual(player.subtitle, "Africa")
        XCTAssertEqual(player.playerItems[2].audioUri, "file:///crocodile.mp3")
        XCTAssertEqual(player.playerItems[2].imageUri, "file:///crocodile.jpg")
    }

    func testInitDefaultsMissingFieldsToEmptyStrings() {
        let player = NativeAudioPlayer([["id": "1"]])

        XCTAssertEqual(player.currentId, "1")
        XCTAssertEqual(player.title, "")
        XCTAssertEqual(player.subtitle, "")
        XCTAssertEqual(player.playerItems[0].audioUri, "")
        XCTAssertEqual(player.playerItems[0].imageUri, "")
    }

    func testNextWrapsAroundToTheFirstItem() {
        let player = makePlayer()

        // load() cannot succeed without real audio files, but the index still
        // has to move -- that is the part worth pinning down here
        _ = player.next()
        XCTAssertEqual(player.currentId, "2")

        _ = player.next()
        XCTAssertEqual(player.currentId, "3")

        _ = player.next()
        XCTAssertEqual(player.currentId, "1")
    }

    func testPreviousWrapsAroundToTheLastItem() {
        let player = makePlayer()

        _ = player.previous()
        XCTAssertEqual(player.currentId, "3")

        _ = player.previous()
        XCTAssertEqual(player.currentId, "2")
    }

    func testSelectSwitchesToTheGivenItem() {
        let player = makePlayer()

        _ = player.select("3")

        XCTAssertEqual(player.currentId, "3")
        XCTAssertEqual(player.title, "Crocodile")
    }

    // MARK: - End of an item
    //
    // See AudioPlayerState in definitions.ts: an item that plays out reports completed, stays
    // selected, and is rewound so a following play() starts it again rather than finding
    // nothing left to play.

    func testAnItemThatPlaysOutIsRewoundAndReported() throws {
        let audio = try writeAudioFile(at: "played-out.wav", seconds: 5)
        let player = NativeAudioPlayer([["id": "1", "audioUri": audio.absoluteString]])
        var completed: [String] = []
        player.onCompleted = { completed.append($0) }

        XCTAssertTrue(player.load())
        player.seekTo(4)
        // the player quantises a seek to a sample boundary, so positions never compare exactly
        XCTAssertEqual(player.position, 4, accuracy: 0.05)

        player.audioPlayerDidFinishPlaying(try XCTUnwrap(player.audioPlayer), successfully: true)

        XCTAssertEqual(player.position, 0, accuracy: 0.05)
        XCTAssertEqual(completed, ["1"])
        XCTAssertEqual(player.currentId, "1")
    }

    func testAnItemThatFailedToPlayOutIsLeftAlone() throws {
        let audio = try writeAudioFile(at: "failed.wav", seconds: 5)
        let player = NativeAudioPlayer([["id": "1", "audioUri": audio.absoluteString]])
        var completed: [String] = []
        player.onCompleted = { completed.append($0) }

        XCTAssertTrue(player.load())
        player.seekTo(4)

        player.audioPlayerDidFinishPlaying(try XCTUnwrap(player.audioPlayer), successfully: false)

        // nothing played out, so there is nothing to report and nothing to rewind
        XCTAssertEqual(player.position, 4, accuracy: 0.05)
        XCTAssertTrue(completed.isEmpty)
    }

    // The plugin holds a player over an empty item list until start() succeeds,
    // so every accessor below has to stay reachable without a current item.

    func testMetadataIsEmptyWithoutItems() {
        let player = NativeAudioPlayer([])

        XCTAssertNil(player.currentItem)
        XCTAssertEqual(player.currentId, "")
        XCTAssertEqual(player.title, "")
        XCTAssertEqual(player.subtitle, "")
    }

    func testNavigationFailsWithoutItems() {
        let player = NativeAudioPlayer([])

        XCTAssertFalse(player.next())
        XCTAssertFalse(player.previous())
        XCTAssertFalse(player.select("1"))

        // previous() used to land on index -1, which trapped on the next read
        XCTAssertEqual(player.currentIndex, 0)
    }

    func testLoadFailsWithoutItems() {
        XCTAssertFalse(NativeAudioPlayer([]).load())
    }

    func testLoadFailsForAnItemWithoutAnAudioUri() {
        XCTAssertFalse(NativeAudioPlayer([["id": "1"]]).load())
    }

    func testInitLockScreenIsANoOpWithoutItems() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        NativeAudioPlayer([]).initLockScreen()

        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }

    func testUpdateLockScreenIsANoOpWithoutNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        // reached through pause() and seekTo() before anything ever loaded, where writing
        // the two fields on their own would put a player on the lock screen that has no
        // title, no artwork and nothing to play
        makePlayer().updateLockScreen()

        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }

    func testAudioOutputMapsTheBuiltInPorts() {
        XCTAssertEqual(NativeAudioPlayer.audioOutput(for: .builtInReceiver), "earpiece")
        XCTAssertEqual(NativeAudioPlayer.audioOutput(for: .builtInSpeaker), "speaker")
    }

    func testAudioOutputReportsExternalRoutesAsExternal() {
        // the earpiece/speaker override does not apply to these, so neither value would be true
        XCTAssertEqual(NativeAudioPlayer.audioOutput(for: .bluetoothA2DP), "external")
        XCTAssertEqual(NativeAudioPlayer.audioOutput(for: .headphones), "external")
        XCTAssertEqual(NativeAudioPlayer.audioOutput(for: nil), "external")
    }

    func testEveryOutputChangeIsReported() {
        let player = makePlayer()
        var reported: [String] = []
        player.onAudioOutputChanged = { reported.append($0) }

        // an output that stays the same is still a different device -- swapping one bluetooth
        // device for another has to reach the app, see the behaviour overview in the README
        player.notifyAudioOutputChange()
        player.notifyAudioOutputChange()

        XCTAssertEqual(reported.count, 2)
    }

    // An interruption -- an incoming call, Siri, or another app taking the audio session --
    // stops playback and is reported as a pause. It is never resumed on its own, see
    // AudioPlayerState in definitions.ts.

    private func postInterruption(_ type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions = []) {
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [
                AVAudioSessionInterruptionTypeKey: type.rawValue,
                AVAudioSessionInterruptionOptionKey: options.rawValue
            ]
        )
    }

    func testAnInterruptionReportsThePlaybackItStopped() throws {
        let audio = try writeAudioFile(at: "interrupted.wav", seconds: 5)
        let player = NativeAudioPlayer([["id": "1", "audioUri": audio.absoluteString]])
        var interruptions = 0
        player.onInterrupted = { interruptions += 1 }

        XCTAssertTrue(player.load())
        player.observeInterruptions()
        player.play()
        XCTAssertTrue(player.playWhenReady)

        postInterruption(.began)

        XCTAssertEqual(interruptions, 1)
        XCTAssertFalse(player.playWhenReady)
        XCTAssertEqual(player.audioPlayer?.isPlaying, false)
    }

    func testAnInterruptionOfAPausedPlayerReportsNothing() throws {
        let audio = try writeAudioFile(at: "not-playing.wav", seconds: 5)
        let player = NativeAudioPlayer([["id": "1", "audioUri": audio.absoluteString]])
        var interruptions = 0
        player.onInterrupted = { interruptions += 1 }

        XCTAssertTrue(player.load())
        player.observeInterruptions()

        // nothing was playing, so nothing was interrupted -- a state is reported per change,
        // and this one changed nothing
        postInterruption(.began)

        XCTAssertEqual(interruptions, 0)
    }

    func testAnInterruptionThatEndsDoesNotResume() throws {
        let audio = try writeAudioFile(at: "resumable.wav", seconds: 5)
        let player = NativeAudioPlayer([["id": "1", "audioUri": audio.absoluteString]])
        var interruptions = 0
        player.onInterrupted = { interruptions += 1 }

        XCTAssertTrue(player.load())
        player.observeInterruptions()
        player.play()

        postInterruption(.began)
        // the system asks for playback back, and is deliberately not given it -- resuming is
        // left to the app, the way it is for an output change
        postInterruption(.ended, options: .shouldResume)

        XCTAssertEqual(interruptions, 1)
        XCTAssertFalse(player.playWhenReady)
        XCTAssertEqual(player.audioPlayer?.isPlaying, false)
    }

    /// Only that play() still starts the player once the session was taken away. Whether the
    /// audio is actually audible is not something a test can see: AVAudioPlayer runs its clock
    /// on an inactive session too, so isPlaying and the position read the same either way, and
    /// there is no way to ask a session whether it is active. The simulator has no audio output
    /// to listen to in the first place -- that part belongs on a device.
    func testPlayStartsThePlayerAfterTheSessionWasDeactivated() throws {
        let audio = try writeAudioFile(at: "deactivated.wav", seconds: 5)
        let player = NativeAudioPlayer([["id": "1", "audioUri": audio.absoluteString]])

        XCTAssertTrue(player.load())

        // what an interruption leaves behind when the reactivation at the end of it did not
        // get the session back
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        player.play()

        XCTAssertEqual(player.audioPlayer?.isPlaying, true)
        XCTAssertTrue(player.playWhenReady)
    }

    func testANotificationWithoutAnInterruptionTypeIsIgnored() throws {
        let audio = try writeAudioFile(at: "malformed.wav", seconds: 5)
        let player = NativeAudioPlayer([["id": "1", "audioUri": audio.absoluteString]])
        var interruptions = 0
        player.onInterrupted = { interruptions += 1 }

        XCTAssertTrue(player.load())
        player.observeInterruptions()
        player.play()

        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil)

        XCTAssertEqual(interruptions, 0)
        XCTAssertTrue(player.playWhenReady)
    }
}
