import XCTest
import MediaPlayer
@testable import NativeAudioPlayerPlugin

class NativeAudioPlayerTests: XCTestCase {

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

    func testSelectKeepsTheCurrentItemForAnUnknownId() {
        let player = makePlayer()

        _ = player.select("does-not-exist")

        XCTAssertEqual(player.currentId, "1")
    }

    func testDurationAndPositionAreZeroWithoutLoadedAudio() {
        let player = makePlayer()

        XCTAssertEqual(player.duration, 0)
        XCTAssertEqual(player.position, 0)
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

    func testAnOutputChangeIsReportedOnce() {
        let player = makePlayer()
        var reported: [(output: String, didPause: Bool)] = []
        player.onAudioOutputChanged = { output, didPause in
            reported.append((output, didPause))
        }

        // a route the host machine does not have, so the first call is always a change
        player.notifiedAudioOutput = "earpiece"
        player.notifyAudioOutputChange()
        player.notifyAudioOutputChange()

        XCTAssertEqual(reported.count, 1)
        XCTAssertNotEqual(reported.first?.output, "earpiece")

        // nothing was loaded, so nothing was playing and no pause is announced
        XCTAssertEqual(reported.first?.didPause, false)
    }

    func testAnUnchangedOutputIsNotReported() {
        let player = makePlayer()
        var reported = 0
        player.onAudioOutputChanged = { _, _ in
            reported += 1
        }

        player.notifiedAudioOutput = player.audioOutput
        player.notifyAudioOutputChange()

        XCTAssertEqual(reported, 0)
    }
}
