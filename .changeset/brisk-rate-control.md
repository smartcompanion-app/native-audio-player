---
'@smartcompanion/native-audio-player': minor
---

Add `setRate({ value })` and `getRate()` to play audio faster or slower, from `0.5` to `2` times normal speed, with the pitch kept so speech stays listenable. The rate belongs to the player rather than to an item: it carries across `next()`, `previous()`, `select()`, an output change, and `stop()` followed by a new `start()`, and it can be set before anything is loaded. A rate outside the range is rejected and leaves the current one in place. The lock screen and the notification follow the rate, so their scrubber keeps pace with the audio.
