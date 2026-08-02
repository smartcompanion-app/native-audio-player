import XCTest
import MediaPlayer
@testable import NativeAudioPlayerPlugin

class NativeAudioPlayerPluginTests: PluginTestCase {

    // MARK: - Calls before start()
    //
    // Every one of these used to trap on playerItems[currentIndex], because the
    // plugin starts out holding a NativeAudioPlayer over an empty item list.

    func testStopBeforeStartResolvesAndReportsAnEmptyId() {
        let plugin = RecordingPlugin()
        let recorder = CallRecorder()

        plugin.stop(recorder.makeCall())

        XCTAssertTrue(recorder.answered)
        XCTAssertNil(recorder.rejected)
        XCTAssertEqual(plugin.states, ["paused"])
        XCTAssertEqual(plugin.events.first?.data["id"] as? String, "")
    }

    func testPlayBeforeStartRejects() {
        let plugin = RecordingPlugin()
        let recorder = CallRecorder()

        plugin.play(recorder.makeCall())

        // resolving used to announce a playing state with nothing behind it
        XCTAssertEqual(recorder.rejected, "could not play without a loaded audio item")
        XCTAssertTrue(plugin.states.isEmpty)
    }

    func testPauseBeforeStartRejects() {
        let plugin = RecordingPlugin()
        let recorder = CallRecorder()

        plugin.pause(recorder.makeCall())

        XCTAssertEqual(recorder.rejected, "could not play without a loaded audio item")
        XCTAssertTrue(plugin.states.isEmpty)
    }

    func testSeekToBeforeStartRejects() {
        let plugin = RecordingPlugin()
        let recorder = CallRecorder()

        plugin.seekTo(recorder.makeCall(["position": 3]))

        XCTAssertEqual(recorder.rejected, "could not play without a loaded audio item")
    }

    func testSelectNextAndPreviousBeforeStartReject() {
        let plugin = RecordingPlugin()
        let selectRecorder = CallRecorder()
        let nextRecorder = CallRecorder()
        let previousRecorder = CallRecorder()

        plugin.select(selectRecorder.makeCall(["id": "1"]))
        plugin.next(nextRecorder.makeCall())
        plugin.previous(previousRecorder.makeCall())

        XCTAssertEqual(selectRecorder.rejected, "could not switch to item with given id")
        XCTAssertEqual(nextRecorder.rejected, "could not switch to next item")
        XCTAssertEqual(previousRecorder.rejected, "could not switch to previous item")
    }

    func testSetEarpieceAndSetSpeakerBeforeStartReject() {
        let plugin = RecordingPlugin()
        let earpieceRecorder = CallRecorder()
        let speakerRecorder = CallRecorder()

        plugin.setEarpiece(earpieceRecorder.makeCall())
        plugin.setSpeaker(speakerRecorder.makeCall())

        XCTAssertNotNil(earpieceRecorder.rejected)
        XCTAssertNotNil(speakerRecorder.rejected)
        XCTAssertTrue(plugin.states.isEmpty)
    }

    func testGetPositionAndGetDurationBeforeStartReturnZero() {
        let plugin = RecordingPlugin()
        let positionRecorder = CallRecorder()
        let durationRecorder = CallRecorder()

        plugin.getPosition(positionRecorder.makeCall())
        plugin.getDuration(durationRecorder.makeCall())

        XCTAssertEqual(positionRecorder.resolved?["value"] as? Int, 0)
        XCTAssertEqual(durationRecorder.resolved?["value"] as? Int, 0)
    }

    func testStartWithEmptyItemsRejects() {
        let plugin = RecordingPlugin()
        let recorder = CallRecorder()

        plugin.start(recorder.makeCall(["items": []]))

        XCTAssertEqual(recorder.rejected, "could not load audio items")
    }

    func testStartWithoutAnItemsKeyRejects() {
        let plugin = RecordingPlugin()
        let recorder = CallRecorder()

        plugin.start(recorder.makeCall())

        XCTAssertEqual(recorder.rejected, "could not load audio items")
    }

    // MARK: - start() with real files

    func testStartResolvesWithTheFirstItemId() throws {
        let audio = try writeAudioFile(at: "first.wav")
        let plugin = RecordingPlugin()
        let recorder = CallRecorder()

        plugin.start(recorder.makeCall(["items": [item(id: "1", audio: audio)]]))

        XCTAssertNil(recorder.rejected)
        XCTAssertEqual(recorder.resolved?["id"] as? String, "1")
    }

    /// The uri used to be reduced to its last path component and re-rooted in the
    /// documents directory, so anything but a flat Directory.Data file failed.
    func testStartResolvesUrisPointingOutsideTheDocumentsDirectory() throws {
        let audio = try writeAudioFile(at: "nested/deeper/track.wav")
        let plugin = RecordingPlugin()
        let recorder = CallRecorder()

        plugin.start(recorder.makeCall(["items": [item(id: "nested", audio: audio)]]))

        XCTAssertNil(recorder.rejected)
        XCTAssertEqual(recorder.resolved?["id"] as? String, "nested")
    }

    func testStartAcceptsAPlainPathAsWellAsAFileUrl() throws {
        let audio = try writeAudioFile(at: "plain.wav")
        let plugin = RecordingPlugin()
        let recorder = CallRecorder()

        plugin.start(recorder.makeCall(["items": [[
            "id": "plain",
            "title": "Plain",
            "subtitle": "Path",
            "audioUri": audio.path,
            "imageUri": ""
        ]]]))

        XCTAssertNil(recorder.rejected)
        XCTAssertEqual(recorder.resolved?["id"] as? String, "plain")
    }

    func testStartRejectsWhenTheAudioFileIsMissing() {
        let plugin = RecordingPlugin()
        let recorder = CallRecorder()
        let missing = sandbox.appendingPathComponent("gone.wav")

        plugin.start(recorder.makeCall(["items": [item(id: "1", audio: missing)]]))

        XCTAssertEqual(recorder.rejected, "could not load audio items")
    }

    // MARK: - Lifetime
    //
    // The plugin used to be kept alive by two strong references: the onCompleted
    // method reference stored on the player, and the six MPRemoteCommandCenter
    // target blocks, which that process-wide singleton never releases.

    func testPluginIsReleasedAfterStop() throws {
        let audio = try writeAudioFile(at: "lifetime.wav")
        weak var weakPlugin: RecordingPlugin?

        autoreleasepool {
            let plugin = RecordingPlugin()
            weakPlugin = plugin

            plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
            plugin.stop(CallRecorder().makeCall())
        }

        XCTAssertNil(weakPlugin, "plugin leaked -- check [weak self] on onCompleted and the remote command targets")
    }

    /// A failed start() replaces the player that was loaded, so the targets from the
    /// previous start would be left driving a player nothing can reach any more.
    func testFailedStartRemovesTheTargetsOfTheStartBeforeIt() throws {
        let audio = try writeAudioFile(at: "failed-restart.wav")
        let plugin = RecordingPlugin()

        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        XCTAssertNotNil(plugin.playTarget)

        let recorder = CallRecorder()
        plugin.start(recorder.makeCall(["items": []]))

        XCTAssertEqual(recorder.rejected, "could not load audio items")
        XCTAssertNil(plugin.pauseTarget)
        XCTAssertNil(plugin.playTarget)
        XCTAssertNil(plugin.toggleTarget)
        XCTAssertNil(plugin.nextTarget)
        XCTAssertNil(plugin.previousTarget)
        XCTAssertNil(plugin.seekTarget)
    }

    func testPluginIsReleasedWithoutAnExplicitStop() throws {
        let audio = try writeAudioFile(at: "lifetime-no-stop.wav")
        weak var weakPlugin: RecordingPlugin?

        autoreleasepool {
            let plugin = RecordingPlugin()
            weakPlugin = plugin

            plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        }

        XCTAssertNil(weakPlugin, "plugin leaked -- deinit has to drop the remote command targets")
    }
}
