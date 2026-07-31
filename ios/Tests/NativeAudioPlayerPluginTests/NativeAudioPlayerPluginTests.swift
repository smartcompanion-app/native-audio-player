import XCTest
import Capacitor
import MediaPlayer
import UIKit
@testable import NativeAudioPlayerPlugin

/// Captures the events the plugin emits. Overriding `notifyListeners`
/// keeps these tests free of a `CapacitorBridge`, which cannot be built headless.
private class RecordingPlugin: NativeAudioPlayerPlugin {
    private(set) var events: [(name: String, data: [String: Any])] = []

    override func notifyListeners(_ eventName: String, data: [String: Any]?) {
        events.append((eventName, data ?? [:]))
    }

    var states: [String] {
        events.compactMap { $0.data["state"] as? String }
    }
}

/// Records how a call was answered. `answered` stays false if a code path
/// forgets to resolve or reject, which would hang the promise in JS.
private class CallRecorder {
    private(set) var resolved: [String: Any]?
    private(set) var rejected: String?
    private(set) var answered = false

    func makeCall(_ options: [String: Any] = [:]) -> CAPPluginCall {
        // coerced the same way CapacitorBridge does before invoking a plugin, so
        // the typed accessors in the plugin see the shape they see in production
        let coerced = JSTypes.coerceDictionaryToJSObject(options as NSDictionary, formattingDatesAsStrings: true) ?? [:]

        return CAPPluginCall(
            callbackId: "test",
            methodName: "test",
            options: coerced,
            success: { [weak self] result, _ in
                self?.answered = true
                self?.resolved = result?.data ?? [:]
            },
            error: { [weak self] error in
                self?.answered = true
                self?.rejected = error?.message
            }
        )
    }
}

class NativeAudioPlayerPluginTests: XCTestCase {

    private var sandbox = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        try super.setUpWithError()
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    /// A silent 16-bit mono WAV. Written at runtime so the repo stays free of
    /// binary assets, and just enough of a file for AVAudioPlayer to open it.
    private func writeAudioFile(at relativePath: String) throws -> URL {
        let sampleRate = 8000
        let frames = sampleRate / 10
        let dataSize = frames * 2

        var data = Data()
        func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func append(uint32 value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append(uint16 value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF")
        append(uint32: UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        append(uint32: 16)
        append(uint16: 1)
        append(uint16: 1)
        append(uint32: UInt32(sampleRate))
        append(uint32: UInt32(sampleRate * 2))
        append(uint16: 2)
        append(uint16: 16)
        append("data")
        append(uint32: UInt32(dataSize))
        data.append(Data(count: dataSize))

        let url = sandbox.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private func writeImageFile(at relativePath: String) throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let data = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }.pngData()

        let url = sandbox.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(data).write(to: url)
        return url
    }

    private func item(id: String, audio: URL, image: URL? = nil) -> [String: Any] {
        return [
            "id": id,
            "title": "Title \(id)",
            "subtitle": "Subtitle \(id)",
            "audioUri": audio.absoluteString,
            "imageUri": image?.absoluteString ?? "\(sandbox.absoluteString)missing-\(id).jpg"
        ]
    }

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

    func testPlayAndPauseBeforeStartResolve() {
        let plugin = RecordingPlugin()
        let playRecorder = CallRecorder()
        let pauseRecorder = CallRecorder()

        plugin.play(playRecorder.makeCall())
        plugin.pause(pauseRecorder.makeCall())

        XCTAssertTrue(playRecorder.answered)
        XCTAssertTrue(pauseRecorder.answered)
        XCTAssertEqual(plugin.states, ["playing", "paused"])
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

    func testSetEarpieceAndSetSpeakerBeforeStartResolve() {
        let plugin = RecordingPlugin()
        let earpieceRecorder = CallRecorder()
        let speakerRecorder = CallRecorder()

        plugin.setEarpiece(earpieceRecorder.makeCall())
        plugin.setSpeaker(speakerRecorder.makeCall())

        XCTAssertTrue(earpieceRecorder.answered)
        XCTAssertTrue(speakerRecorder.answered)
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

    // MARK: - Lock screen metadata

    func testNowPlayingInfoUsesTheCurrentItemMetadata() throws {
        let audio = try writeAudioFile(at: "meta.wav")
        let image = try writeImageFile(at: "meta.png")
        let plugin = RecordingPlugin()

        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio, image: image)]]))

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "Title 1")
        XCTAssertEqual(info?[MPMediaItemPropertyArtist] as? String, "Subtitle 1")
        XCTAssertNotNil(info?[MPMediaItemPropertyArtwork])
    }

    /// The artwork request handler used to force unwrap UIImage(contentsOfFile:),
    /// which crashed on an arbitrary thread whenever the system asked for it.
    func testStartOmitsArtworkWhenTheImageIsMissing() throws {
        let audio = try writeAudioFile(at: "no-art.wav")
        let plugin = RecordingPlugin()
        let recorder = CallRecorder()

        plugin.start(recorder.makeCall(["items": [item(id: "1", audio: audio)]]))

        XCTAssertNil(recorder.rejected)
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "Title 1")
        XCTAssertNil(info?[MPMediaItemPropertyArtwork])
    }

    func testStopClearsNowPlayingInfo() throws {
        let audio = try writeAudioFile(at: "clear.wav")
        let plugin = RecordingPlugin()

        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        XCTAssertNotNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)

        plugin.stop(CallRecorder().makeCall())
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }

    // MARK: - Lifetime
    //
    // The plugin used to be kept alive by two strong references: the onCompleted
    // method reference stored on the player, and the five MPRemoteCommandCenter
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
