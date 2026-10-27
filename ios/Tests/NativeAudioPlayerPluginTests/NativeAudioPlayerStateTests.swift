import XCTest
@testable import NativeAudioPlayerPlugin

/// getState(), the one way to read the player rather than follow it. The state is otherwise only
/// observable through audioPlayerChange, so an app that mounts late or missed an event has
/// nothing to recover it from -- see getState in definitions.ts.
class NativeAudioPlayerStateTests: PluginTestCase {

    private func state(of plugin: RecordingPlugin) throws -> [String: Any] {
        let recorder = CallRecorder()
        plugin.getState(recorder.makeCall())

        XCTAssertTrue(recorder.answered, "getState() left the call unanswered")
        XCTAssertNil(recorder.rejected)
        return try XCTUnwrap(recorder.resolved)
    }

    func testStateBeforeStartIsStoppedWithNothingLoaded() throws {
        let state = try state(of: RecordingPlugin())

        XCTAssertEqual(state["id"] as? String, "")
        XCTAssertEqual(state["state"] as? String, "stopped")
        XCTAssertEqual(state["position"] as? TimeInterval, 0)
        XCTAssertEqual(state["duration"] as? TimeInterval, 0)
    }

    func testStateAfterStartIsTheFirstItemPaused() throws {
        let audio = try writeAudioFile(at: "state-start.wav", seconds: 5)
        let plugin = RecordingPlugin()

        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        let state = try state(of: plugin)

        XCTAssertEqual(state["id"] as? String, "1")
        XCTAssertEqual(state["state"] as? String, "paused")
        XCTAssertEqual(try XCTUnwrap(state["position"] as? TimeInterval), 0, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(state["duration"] as? TimeInterval), 5, accuracy: 0.05)
    }

    func testStateFollowsPlaybackAsItStartsAndStops() throws {
        let audio = try writeAudioFile(at: "state-playing.wav", seconds: 5)
        let plugin = RecordingPlugin()
        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))

        plugin.play(CallRecorder().makeCall())
        XCTAssertEqual(try state(of: plugin)["state"] as? String, "playing")

        waitUntil { ((try? self.state(of: plugin)["position"] as? TimeInterval) ?? 0) > 0 }
        plugin.pause(CallRecorder().makeCall())

        let paused = try state(of: plugin)
        XCTAssertEqual(paused["state"] as? String, "paused")
        XCTAssertGreaterThan(try XCTUnwrap(paused["position"] as? TimeInterval), 0)
    }

    func testStateFollowsTheSelectedItem() throws {
        let first = try writeAudioFile(at: "state-1.wav", seconds: 5)
        let second = try writeAudioFile(at: "state-2.wav", seconds: 3)
        let plugin = RecordingPlugin()
        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: first), item(id: "2", audio: second)]]))

        plugin.next(CallRecorder().makeCall())
        let state = try state(of: plugin)

        XCTAssertEqual(state["id"] as? String, "2")
        XCTAssertEqual(state["state"] as? String, "paused")
        XCTAssertEqual(try XCTUnwrap(state["duration"] as? TimeInterval), 3, accuracy: 0.05)
    }

    func testAnItemThatPlayedOutIsPausedOnItsStart() throws {
        let audio = try writeAudioFile(at: "state-completed.wav", seconds: 0.3)
        let plugin = RecordingPlugin()
        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))

        plugin.play(CallRecorder().makeCall())
        waitUntil { plugin.states.contains("completed") }
        XCTAssertTrue(plugin.states.contains("completed"), "the item never played out")

        let state = try state(of: plugin)
        XCTAssertEqual(state["id"] as? String, "1")
        XCTAssertEqual(state["state"] as? String, "paused")
        XCTAssertEqual(try XCTUnwrap(state["position"] as? TimeInterval), 0, accuracy: 0.05)
    }

    func testStateAfterStopIsStoppedAgain() throws {
        let audio = try writeAudioFile(at: "state-stop.wav", seconds: 5)
        let plugin = RecordingPlugin()
        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        plugin.play(CallRecorder().makeCall())

        plugin.stop(CallRecorder().makeCall())
        let state = try state(of: plugin)

        XCTAssertEqual(state["id"] as? String, "")
        XCTAssertEqual(state["state"] as? String, "stopped")
        XCTAssertEqual(state["position"] as? TimeInterval, 0)
        XCTAssertEqual(state["duration"] as? TimeInterval, 0)
    }

    func testAskingForTheStateReportsNothing() throws {
        let audio = try writeAudioFile(at: "state-quiet.wav", seconds: 5)
        let plugin = RecordingPlugin()
        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))

        _ = try state(of: plugin)

        XCTAssertTrue(plugin.events.isEmpty)
    }
}
