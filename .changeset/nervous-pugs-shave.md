---
'@smartcompanion/native-audio-player': patch
---

Expand the README with a quick-start usage example covering the full lifecycle: handing over a playlist with `start()`, following the `update` event, the playback and routing calls, and tearing down with `stop()`.

Document that `audioUri` and `imageUri` have to be local file URIs on Android and iOS, including a helper that downloads a remote file into `Directory.Data`, and note that iOS resolves the file by its name in the documents directory, so files need to stay flat in that folder.

Also record the behaviour that is not obvious from the API signatures: `start()` prepares the playlist but does not begin playback, the player emits `completed` at the end of an item instead of advancing on its own, positions and durations are whole seconds, and `setEarpiece()`/`setSpeaker()` only override the built-in output.
