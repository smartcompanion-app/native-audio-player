import XCTest
import MediaPlayer
@testable import NativeAudioPlayerPlugin

/// The playback rate. Spoken word -- audio guides, narration -- is often listened to faster or
/// slower than it was recorded, see setRate in definitions.ts.
///
/// AVAudioPlayer only honours a rate when enableRate was set before prepareToPlay(), and the
/// player is rebuilt for every item and every output change -- so most of what is pinned down
/// here is that the rate reaches each new one.
class NativeAudioPlayerRateTests: PluginTestCase {

    private func rate(of plugin: RecordingPlugin) throws -> Double {
        let recorder = CallRecorder()
        plugin.getRate(recorder.makeCall())
        return try XCTUnwrap(recorder.resolved?["value"] as? Double)
    }

    private func setRate(_ value: Any?, on plugin: RecordingPlugin) -> CallRecorder {
        let recorder = CallRecorder()
        plugin.setRate(recorder.makeCall(value.map { ["value": $0] } ?? [:]))
        return recorder
    }

    private func lockScreenRate() -> Double? {
        (MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue
    }

    private func startedPlugin(ids: [String] = ["1"]) throws -> RecordingPlugin {
        let items = try ids.map { item(id: $0, audio: try writeAudioFile(at: "rate-\($0)-\(UUID().uuidString).wav", seconds: 5)) }
        let plugin = RecordingPlugin()
        plugin.start(CallRecorder().makeCall(["items": items]))
        return plugin
    }

    // MARK: - The player

    func testALoadedPlayerIsPreparedToChangeItsRate() throws {
        let audio = try writeAudioFile(at: "rate-enabled.wav", seconds: 5)
        let player = NativeAudioPlayer([["id": "1", "audioUri": audio.absoluteString]])
        player.rate = 1.5

        XCTAssertTrue(player.load())

        XCTAssertEqual(player.audioPlayer?.enableRate, true)
        XCTAssertEqual(try XCTUnwrap(player.audioPlayer?.rate), 1.5, accuracy: 0.001)
    }

    // MARK: - The plugin

    func testPlaysAtNormalSpeedUntilToldOtherwise() throws {
        XCTAssertEqual(try rate(of: RecordingPlugin()), 1)
        XCTAssertEqual(try rate(of: try startedPlugin()), 1)
    }

    func testReportsTheRateItWasGiven() throws {
        let plugin = try startedPlugin()

        let recorder = setRate(1.5, on: plugin)

        XCTAssertNil(recorder.rejected)
        XCTAssertTrue(recorder.answered)
        XCTAssertEqual(try rate(of: plugin), 1.5)
    }

    func testPlaysTheAudioAtThatRate() throws {
        let plugin = try startedPlugin()
        _ = setRate(2, on: plugin)

        plugin.play(CallRecorder().makeCall())
        spin(for: 1)
        plugin.pause(CallRecorder().makeCall())

        // two seconds of audio in one second of playback, with room for when the clock started
        let recorder = CallRecorder()
        plugin.getPosition(recorder.makeCall())
        let position = try XCTUnwrap(recorder.resolved?["value"] as? TimeInterval)
        XCTAssertGreaterThan(position, 1.5)
        XCTAssertLessThan(position, 2.6)
    }

    func testCanBeSetBeforeStartAndAppliesOnceSomethingIsLoaded() throws {
        let plugin = RecordingPlugin()
        XCTAssertNil(setRate(0.5, on: plugin).rejected)

        let audio = try writeAudioFile(at: "rate-before-start.wav", seconds: 5)
        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        plugin.play(CallRecorder().makeCall())

        XCTAssertEqual(try rate(of: plugin), 0.5)
        XCTAssertEqual(try XCTUnwrap(lockScreenRate()), 0.5, accuracy: 0.001)
    }

    func testSurvivesAChangeOfItem() throws {
        let plugin = try startedPlugin(ids: ["1", "2"])
        _ = setRate(2, on: plugin)

        plugin.next(CallRecorder().makeCall())
        plugin.play(CallRecorder().makeCall())

        XCTAssertEqual(try rate(of: plugin), 2)
        XCTAssertEqual(try XCTUnwrap(lockScreenRate()), 2, accuracy: 0.001)

        plugin.select(CallRecorder().makeCall(["id": "1"]))
        plugin.play(CallRecorder().makeCall())

        XCTAssertEqual(try XCTUnwrap(lockScreenRate()), 2, accuracy: 0.001)
    }

    /// Switching the output rebuilds the player as well.
    func testSurvivesAChangeOfOutput() throws {
        let plugin = try startedPlugin()
        _ = setRate(1.5, on: plugin)

        plugin.setEarpiece(CallRecorder().makeCall())
        plugin.play(CallRecorder().makeCall())

        XCTAssertEqual(try XCTUnwrap(lockScreenRate()), 1.5, accuracy: 0.001)
    }

    func testSurvivesAStopAndANewStart() throws {
        let plugin = try startedPlugin()
        _ = setRate(1.5, on: plugin)

        plugin.stop(CallRecorder().makeCall())
        let audio = try writeAudioFile(at: "rate-restart.wav", seconds: 5)
        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        plugin.play(CallRecorder().makeCall())

        XCTAssertEqual(try rate(of: plugin), 1.5)
        XCTAssertEqual(try XCTUnwrap(lockScreenRate()), 1.5, accuracy: 0.001)
    }

    func testRejectsARateOutsideTheRangeAndKeepsTheOneItHad() throws {
        let plugin = try startedPlugin()
        _ = setRate(1.5, on: plugin)

        for value in [0.25, 2.5, 0, -1] {
            XCTAssertNotNil(setRate(value, on: plugin).rejected, "setRate(\(value)) was accepted")
        }
        XCTAssertNotNil(setRate(nil, on: plugin).rejected, "setRate() without a value was accepted")

        XCTAssertEqual(try rate(of: plugin), 1.5)
    }

    func testAcceptsBothEndsOfTheRange() throws {
        let plugin = try startedPlugin()

        XCTAssertNil(setRate(0.5, on: plugin).rejected)
        XCTAssertEqual(try rate(of: plugin), 0.5)

        XCTAssertNil(setRate(2, on: plugin).rejected)
        XCTAssertEqual(try rate(of: plugin), 2)
    }

    // MARK: - The lock screen
    //
    // The system runs the lock screen clock from the rate it was last given. A playing player
    // reporting 1.0 at double speed has the scrubber fall behind the audio by a second every
    // second; a paused one still has to report 0, or the transport keeps offering pause.

    func testTheLockScreenFollowsTheRateWhilePlaying() throws {
        let plugin = try startedPlugin()
        plugin.play(CallRecorder().makeCall())

        _ = setRate(2, on: plugin)

        XCTAssertEqual(try XCTUnwrap(lockScreenRate()), 2, accuracy: 0.001)
    }

    func testTheLockScreenStillReportsAPausedPlayerAsStopped() throws {
        let plugin = try startedPlugin()

        _ = setRate(2, on: plugin)

        XCTAssertEqual(try XCTUnwrap(lockScreenRate()), 0, accuracy: 0.001)
    }

    func testChangingTheRateReportsNothing() throws {
        let plugin = try startedPlugin()
        plugin.play(CallRecorder().makeCall())
        let before = plugin.events.count

        _ = setRate(2, on: plugin)

        XCTAssertEqual(plugin.events.count, before)
    }
}
