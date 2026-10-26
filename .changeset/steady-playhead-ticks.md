---
'@smartcompanion/native-audio-player': minor
---

Add a `progress` event that reports `{ id, position, duration }` while the audio is playing, so a progress bar can follow playback without polling `getPosition()`. It reports twice a second by default; pass `progressInterval` (in seconds) to `start()` for another interval. It stops with the playback, whatever stopped it, and starts again with the next `playing`.
