import XCTest
import Capacitor
import MediaPlayer
import UIKit
@testable import NativeAudioPlayerPlugin

/// Captures the events the plugin emits. Overriding `notifyListeners`
/// keeps these tests free of a `CapacitorBridge`, which cannot be built headless.
class RecordingPlugin: NativeAudioPlayerPlugin {
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
class CallRecorder {
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

class PluginTestCase: XCTestCase {

    var sandbox = FileManager.default.temporaryDirectory

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
    ///
    /// The default length only has to be openable. Pass a longer one where the test seeks,
    /// since a position past the end of the file is not one the player keeps.
    func writeAudioFile(at relativePath: String, seconds: Double = 0.1) throws -> URL {
        let sampleRate = 8000
        let frames = Int(Double(sampleRate) * seconds)
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

    func writeImageFile(at relativePath: String) throws -> URL {
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

    func item(id: String, audio: URL, image: URL? = nil) -> [String: Any] {
        return [
            "id": id,
            "title": "Title \(id)",
            "subtitle": "Subtitle \(id)",
            "audioUri": audio.absoluteString,
            "imageUri": image?.absoluteString ?? "\(sandbox.absoluteString)missing-\(id).jpg"
        ]
    }
}
