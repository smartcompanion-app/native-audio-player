import XCTest
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
}
