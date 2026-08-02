import XCTest
import MediaPlayer
@testable import NativeAudioPlayerPlugin

class NativeAudioPlayerLockScreenTests: PluginTestCase {

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

    // MARK: - Lock screen playback state
    //
    // The lock screen keeps its own clock, seeded with the elapsed time and advanced at the
    // playback rate it was last handed. The rate used to be hardcoded to 1.0 and neither field
    // was written again after the item loaded, so the controls described a player that was
    // playing from the moment it loaded and never stopped. The visible result was a pause
    // button that never turned back into a play button -- the play command was unreachable --
    // and a scrubber that ran on regardless of where the audio actually was.

    func testStartReportsALoadedItemAsNotPlaying() throws {
        let audio = try writeAudioFile(at: "state.wav")
        let plugin = RecordingPlugin()

        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0.0)
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Int, 0)
    }

    func testPauseReportsThePlayerAsStopped() throws {
        let audio = try writeAudioFile(at: "paused.wav")
        let plugin = RecordingPlugin()

        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        plugin.play(CallRecorder().makeCall())
        plugin.pause(CallRecorder().makeCall())

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0.0)
    }

    func testSeekToMovesTheLockScreenPosition() throws {
        let audio = try writeAudioFile(at: "seek.wav", seconds: 5)
        let plugin = RecordingPlugin()

        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        plugin.seekTo(CallRecorder().makeCall(["position": 3]))

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Int, 3)
    }

    func testNextRestartsTheLockScreenOnTheNewItem() throws {
        let first = try writeAudioFile(at: "first.wav", seconds: 5)
        let second = try writeAudioFile(at: "second.wav", seconds: 5)
        let plugin = RecordingPlugin()

        plugin.start(CallRecorder().makeCall(["items": [
            item(id: "1", audio: first),
            item(id: "2", audio: second)
        ]]))
        plugin.seekTo(CallRecorder().makeCall(["position": 3]))
        plugin.next(CallRecorder().makeCall())

        // next() deliberately leaves the player paused, so the controls have to say so
        // rather than show the new item running from where the old one stopped
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "Title 2")
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0.0)
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Int, 0)
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
        XCTAssertEqual(player.position, 4)

        player.audioPlayerDidFinishPlaying(try XCTUnwrap(player.audioPlayer), successfully: true)

        XCTAssertEqual(player.position, 0)
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
        XCTAssertEqual(player.position, 4)
        XCTAssertTrue(completed.isEmpty)
    }

    // MARK: - Contract edges

    func testSeekingPastTheEndStopsAtTheEnd() throws {
        let audio = try writeAudioFile(at: "past-end.wav", seconds: 5)
        let plugin = RecordingPlugin()

        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        plugin.seekTo(CallRecorder().makeCall(["position": 99]))

        // AVAudioPlayer does not keep a position past the end, so an unclamped seek landed
        // somewhere the player could not play from
        let position = CallRecorder()
        plugin.getPosition(position.makeCall())
        XCTAssertEqual(position.resolved?["value"] as? Int, 5)
    }

    func testSeekingBeforeTheStartStopsAtTheStart() throws {
        let audio = try writeAudioFile(at: "before-start.wav", seconds: 5)
        let plugin = RecordingPlugin()

        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        plugin.seekTo(CallRecorder().makeCall(["position": -10]))

        let position = CallRecorder()
        plugin.getPosition(position.makeCall())
        XCTAssertEqual(position.resolved?["value"] as? Int, 0)
    }

    func testSelectRejectsAnUnknownIdAndKeepsTheCurrentItem() throws {
        let audio = try writeAudioFile(at: "select.wav")
        let plugin = RecordingPlugin()
        let recorder = CallRecorder()

        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        plugin.select(recorder.makeCall(["id": "does-not-exist"]))

        // it used to resolve with the item the caller already had
        XCTAssertEqual(recorder.rejected, "could not switch to item with given id")
        XCTAssertFalse(plugin.states.contains("skip"))
    }

    func testPlayAfterStopRejects() throws {
        let audio = try writeAudioFile(at: "after-stop.wav")
        let plugin = RecordingPlugin()

        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        plugin.stop(CallRecorder().makeCall())

        let recorder = CallRecorder()
        plugin.play(recorder.makeCall())

        XCTAssertEqual(recorder.rejected, "could not play without a loaded audio item")
    }

    func testStopClearsNowPlayingInfo() throws {
        let audio = try writeAudioFile(at: "clear.wav")
        let plugin = RecordingPlugin()

        plugin.start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))
        XCTAssertNotNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)

        plugin.stop(CallRecorder().makeCall())
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }

    // MARK: - Remote commands
    //
    // Every command on the shared command center starts out enabled, so a command the plugin
    // never registers a handler for is still a control the system is willing to draw and
    // nothing will ever answer. The skip pair is the one that costs: while those are enabled
    // the transport shows the fifteen-second skip buttons in place of the track buttons, so
    // next and previous could be registered, enabled, and still never reach the app.

    func testStartDisablesTheCommandsWithoutAHandler() throws {
        let audio = try writeAudioFile(at: "unhandled.wav")
        let commandCenter = MPRemoteCommandCenter.shared()
        let unhandled: [MPRemoteCommand] = [
            commandCenter.skipForwardCommand,
            commandCenter.skipBackwardCommand,
            commandCenter.seekForwardCommand,
            commandCenter.seekBackwardCommand,
            commandCenter.stopCommand
        ]

        // the singleton outlives the test, so start from the state a fresh process has
        // rather than from whatever an earlier test left behind
        for command in unhandled {
            command.isEnabled = true
        }

        RecordingPlugin().start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))

        for command in unhandled {
            XCTAssertFalse(command.isEnabled, "\(command) is offered with nothing to answer it")
        }
    }

    func testStartEnablesTheCommandsItHandles() throws {
        let audio = try writeAudioFile(at: "handled.wav")
        let commandCenter = MPRemoteCommandCenter.shared()

        RecordingPlugin().start(CallRecorder().makeCall(["items": [item(id: "1", audio: audio)]]))

        XCTAssertTrue(commandCenter.playCommand.isEnabled)
        XCTAssertTrue(commandCenter.pauseCommand.isEnabled)
        XCTAssertTrue(commandCenter.togglePlayPauseCommand.isEnabled)
        XCTAssertTrue(commandCenter.nextTrackCommand.isEnabled)
        XCTAssertTrue(commandCenter.previousTrackCommand.isEnabled)
        XCTAssertTrue(commandCenter.changePlaybackPositionCommand.isEnabled)
    }
}
