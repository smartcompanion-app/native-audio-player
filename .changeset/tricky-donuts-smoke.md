---
'@smartcompanion/native-audio-player': patch
---

Fix four things in the web implementation that the new browser test suite turned up:

- `start()` now rejects when an audio file cannot be loaded, instead of leaving the promise pending forever. iOS and Android both already rejected.
- `next()` and `previous()` reject before `start()` and after `stop()`, matching the other two platforms. `previous()` on an empty playlist used to leave the player on an index it could not recover from.
- The browser's own media control now shows whether the audio is playing and keeps its scrubber in step with it, rather than sitting at "paused" on the first moment of the item for as long as it plays.
- Pressing play, pause or seek on that control before `start()` no longer produces an unhandled promise rejection. It is still refused, just quietly.
