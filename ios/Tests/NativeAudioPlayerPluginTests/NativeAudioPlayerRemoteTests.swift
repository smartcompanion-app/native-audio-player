import XCTest
import MediaPlayer
import Capacitor
@testable import NativeAudioPlayerPlugin

/// Audio that is not on the device: an http(s) URL is played from where it is rather than
/// downloaded first -- see Item.audioUri in definitions.ts.
///
/// Served over real HTTP from the loopback interface, so the player goes through the network
/// stack the way it does for a remote file, and the server's log shows it actually did.
class NativeAudioPlayerRemoteTests: PluginTestCase {

    private let server = LocalHTTPServer()

    override func setUpWithError() throws {
        try super.setUpWithError()
        try server.start()
    }

    override func tearDownWithError() throws {
        server.stop()
        try super.tearDownWithError()
    }

    /// Serves a silent WAV of the given length at the path, and returns its URL.
    private func remoteAudio(_ path: String, seconds: Double) throws -> URL {
        let file = try writeAudioFile(at: "remote-\(UUID().uuidString).wav", seconds: seconds)
        server.serve(try Data(contentsOf: file), at: path, contentType: "audio/wav")
        return try server.url(for: path)
    }

    private func remoteItem(id: String, audio: URL, image: URL? = nil) -> [String: Any] {
        [
            "id": id,
            "title": "Title \(id)",
            "subtitle": "Subtitle \(id)",
            "audioUri": audio.absoluteString,
            "imageUri": image?.absoluteString ?? ""
        ]
    }

    private func value(_ method: (CAPPluginCall) -> Void) throws -> TimeInterval {
        try XCTUnwrap(answer(method).resolved?["value"] as? TimeInterval)
    }

    func testStartsAPlaylistOfRemoteItems() throws {
        let audio = try remoteAudio("/one.wav", seconds: 5)
        let plugin = RecordingPlugin()

        let recorder = answer(plugin.start, ["items": [remoteItem(id: "1", audio: audio)]])

        XCTAssertNil(recorder.rejected)
        XCTAssertEqual(recorder.resolved?["id"] as? String, "1")
        // start() resolves once the item can be played, so its length is already known
        XCTAssertEqual(try value(plugin.getDuration), 5, accuracy: 0.05)
        XCTAssertTrue(server.requests.contains("/one.wav"), "the audio was never fetched from the server")
    }

    func testPlaysARemoteItem() throws {
        let audio = try remoteAudio("/playing.wav", seconds: 5)
        let plugin = RecordingPlugin()
        answer(plugin.start, ["items": [remoteItem(id: "1", audio: audio)]])

        plugin.play(CallRecorder().makeCall())
        waitUntil { ((try? self.value(plugin.getPosition)) ?? 0) > 0.5 }

        XCTAssertGreaterThan(try value(plugin.getPosition), 0.5)
        XCTAssertEqual(plugin.states, ["playing"])
    }

    func testMovesToAnotherRemoteItem() throws {
        let first = try remoteAudio("/first.wav", seconds: 5)
        let second = try remoteAudio("/second.wav", seconds: 3)
        let plugin = RecordingPlugin()
        answer(plugin.start, ["items": [remoteItem(id: "1", audio: first), remoteItem(id: "2", audio: second)]])

        let recorder = answer(plugin.next)

        XCTAssertEqual(recorder.resolved?["id"] as? String, "2")
        XCTAssertEqual(plugin.states, ["skipped"])
        XCTAssertEqual(try value(plugin.getDuration), 3, accuracy: 0.05)
    }

    func testPlaysARemoteItemOutToItsEnd() throws {
        let audio = try remoteAudio("/short.wav", seconds: 0.5)
        let plugin = RecordingPlugin()
        answer(plugin.start, ["items": [remoteItem(id: "1", audio: audio)]])

        plugin.play(CallRecorder().makeCall())
        waitUntil { plugin.states.contains("completed") }

        XCTAssertEqual(plugin.states, ["playing", "completed"])
        XCTAssertEqual(try value(plugin.getPosition), 0, accuracy: 0.05)
    }

    func testMixesRemoteAndLocalItems() throws {
        let remote = try remoteAudio("/mixed.wav", seconds: 5)
        let local = try writeAudioFile(at: "mixed-local.wav", seconds: 3)
        let plugin = RecordingPlugin()
        answer(plugin.start, ["items": [remoteItem(id: "remote", audio: remote), item(id: "local", audio: local)]])

        XCTAssertEqual(answer(plugin.next).resolved?["id"] as? String, "local")
        XCTAssertEqual(try value(plugin.getDuration), 3, accuracy: 0.05)

        XCTAssertEqual(answer(plugin.previous).resolved?["id"] as? String, "remote")
        XCTAssertEqual(try value(plugin.getDuration), 5, accuracy: 0.05)
    }

    func testRejectsARemoteItemThatCannotBeLoaded() throws {
        let plugin = RecordingPlugin()

        let recorder = answer(plugin.start, ["items": [remoteItem(id: "1", audio: try server.url(for: "/missing.wav"))]])

        XCTAssertEqual(recorder.rejected, "could not load audio items")
        XCTAssertEqual(answer(plugin.getState).resolved?["state"] as? String, "stopped")
    }

    func testRejectsMovingToARemoteItemThatCannotBeLoaded() throws {
        let audio = try remoteAudio("/there.wav", seconds: 5)
        let plugin = RecordingPlugin()
        answer(plugin.start, ["items": [remoteItem(id: "1", audio: audio), remoteItem(id: "2", audio: try server.url(for: "/gone.wav"))]])

        let recorder = answer(plugin.next)

        XCTAssertEqual(recorder.rejected, "could not switch to next item")
        XCTAssertFalse(plugin.states.contains("skipped"))
    }

    /// The lock screen artwork comes from the same kind of place as the audio, so a remote item
    /// usually has a remote image -- which UIImage(contentsOfFile:) cannot read.
    func testShowsRemoteArtworkOnTheLockScreen() throws {
        let audio = try remoteAudio("/art.wav", seconds: 5)
        let image = try writeImageFile(at: "art.png")
        server.serve(try Data(contentsOf: image), at: "/art.png", contentType: "image/png")
        let plugin = RecordingPlugin()

        answer(plugin.start, ["items": [remoteItem(id: "1", audio: audio, image: try server.url(for: "/art.png"))]])
        waitUntil { MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] != nil }

        XCTAssertNotNil(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork])
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Title 1")
    }

    /// Two loads in flight -- next() pressed twice before the first item arrived -- must end on the
    /// item asked for last, with one skip for it rather than one for each.
    func testALoadThatWasOvertakenDoesNotWin() throws {
        let first = try remoteAudio("/a.wav", seconds: 5)
        let second = try remoteAudio("/b.wav", seconds: 4)
        let third = try remoteAudio("/c.wav", seconds: 3)
        let plugin = RecordingPlugin()
        answer(plugin.start, ["items": [
            remoteItem(id: "1", audio: first),
            remoteItem(id: "2", audio: second),
            remoteItem(id: "3", audio: third)
        ]])

        let overtaken = CallRecorder()
        let last = CallRecorder()
        plugin.next(overtaken.makeCall())
        plugin.next(last.makeCall())
        waitUntil { overtaken.answered && last.answered }

        XCTAssertTrue(overtaken.answered, "the overtaken call was never answered")
        XCTAssertEqual(last.resolved?["id"] as? String, "3")
        XCTAssertEqual(plugin.states, ["skipped"])
        XCTAssertEqual(answer(plugin.getState).resolved?["id"] as? String, "3")
        XCTAssertEqual(try value(plugin.getDuration), 3, accuracy: 0.05)
    }
}
