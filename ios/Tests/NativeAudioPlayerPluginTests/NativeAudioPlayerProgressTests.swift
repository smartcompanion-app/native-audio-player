import XCTest
@testable import NativeAudioPlayerPlugin

/// The progress event, which reports the playhead while the audio runs. Before it the only way to
/// follow the playhead was to poll getPosition(), which every app ended up doing for itself --
/// see the progress event in definitions.ts.
///
/// These run a real player on a silent file and let the run loop turn, so the timer is the one
/// the app gets. Counts are bounded on both sides rather than exact: a timer is only as punctual
/// as the run loop that fires it.
class NativeAudioPlayerProgressTests: PluginTestCase {

    private func progress(of plugin: RecordingPlugin) -> [[String: Any]] {
        plugin.events.filter { $0.name == "progress" }.map { $0.data }
    }

    private func startedPlugin(seconds: Double = 5, options: [String: Any] = [:]) throws -> RecordingPlugin {
        let audio = try writeAudioFile(at: "progress-\(UUID().uuidString).wav", seconds: seconds)
        let plugin = RecordingPlugin()
        var startOptions = options
        startOptions["items"] = [item(id: "1", audio: audio)]
        plugin.start(CallRecorder().makeCall(startOptions))
        return plugin
    }

    func testReportsThePlayheadTwiceASecondWhilePlaying() throws {
        let plugin = try startedPlugin()

        plugin.play(CallRecorder().makeCall())
        spin(for: 1.7)

        let progress = progress(of: plugin)
        XCTAssertGreaterThanOrEqual(progress.count, 2)
        XCTAssertLessThanOrEqual(progress.count, 4)

        for event in progress {
            XCTAssertEqual(event["id"] as? String, "1")
            XCTAssertEqual(try XCTUnwrap(event["duration"] as? TimeInterval), 5, accuracy: 0.05)
        }

        let positions = progress.compactMap { $0["position"] as? TimeInterval }
        XCTAssertEqual(positions, positions.sorted())
        XCTAssertGreaterThan(try XCTUnwrap(positions.last), try XCTUnwrap(positions.first))
    }

    func testReportsAtTheIntervalStartWasGiven() throws {
        let plugin = try startedPlugin(options: ["progressInterval": 0.2])

        plugin.play(CallRecorder().makeCall())
        spin(for: 1.1)

        let count = progress(of: plugin).count
        XCTAssertGreaterThanOrEqual(count, 4)
        XCTAssertLessThanOrEqual(count, 6)
    }

    func testAnIntervalThatIsNotAPositiveNumberFallsBackToTheDefault() throws {
        let plugin = try startedPlugin(options: ["progressInterval": 0])

        plugin.play(CallRecorder().makeCall())
        spin(for: 1.2)

        let count = progress(of: plugin).count
        XCTAssertGreaterThanOrEqual(count, 1)
        XCTAssertLessThanOrEqual(count, 3)
    }

    func testReportsNothingBeforePlaybackStarts() throws {
        let plugin = try startedPlugin()

        spin(for: 1.2)

        XCTAssertTrue(progress(of: plugin).isEmpty)
    }

    func testStopsReportingOncePaused() throws {
        let plugin = try startedPlugin()
        plugin.play(CallRecorder().makeCall())
        spin(for: 0.7)

        plugin.pause(CallRecorder().makeCall())
        let reported = progress(of: plugin).count
        spin(for: 1.2)

        XCTAssertEqual(progress(of: plugin).count, reported)
    }

    func testPlayingAgainDoesNotStartASecondTimer() throws {
        let plugin = try startedPlugin()

        plugin.play(CallRecorder().makeCall())
        plugin.pause(CallRecorder().makeCall())
        plugin.play(CallRecorder().makeCall())
        spin(for: 1.7)

        XCTAssertLessThanOrEqual(progress(of: plugin).count, 4)
    }

    func testStopsReportingWhenTheItemIsSkippedAwayFrom() throws {
        let first = try writeAudioFile(at: "progress-skip-1.wav", seconds: 5)
        let second = try writeAudioFile(at: "progress-skip-2.wav", seconds: 5)
        let plugin = RecordingPlugin()
        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: first), item(id: "2", audio: second)]]))
        plugin.play(CallRecorder().makeCall())

        plugin.next(CallRecorder().makeCall())
        let reported = progress(of: plugin).count
        spin(for: 1.2)

        XCTAssertEqual(progress(of: plugin).count, reported)
    }

    func testStopsReportingOnceTheItemPlayedOut() throws {
        let plugin = try startedPlugin(seconds: 0.3)

        plugin.play(CallRecorder().makeCall())
        waitUntil { plugin.states.contains("completed") }
        XCTAssertTrue(plugin.states.contains("completed"), "the item never played out")

        let reported = progress(of: plugin).count
        spin(for: 1.2)

        XCTAssertEqual(progress(of: plugin).count, reported)
    }

    func testStopsReportingAfterStop() throws {
        let plugin = try startedPlugin()
        plugin.play(CallRecorder().makeCall())

        plugin.stop(CallRecorder().makeCall())
        let reported = progress(of: plugin).count
        spin(for: 1.2)

        XCTAssertEqual(progress(of: plugin).count, reported)
    }

    func testAddsNothingToAudioPlayerChange() throws {
        let plugin = try startedPlugin()

        plugin.play(CallRecorder().makeCall())
        spin(for: 1.2)

        XCTAssertEqual(plugin.states, ["playing"])
    }
}
