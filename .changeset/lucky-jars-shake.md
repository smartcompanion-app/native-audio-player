---
'@smartcompanion/native-audio-player': patch
---

Stop iOS and the web implementation reporting a `paused` for a pause that stopped nothing. A scrubber fires an input event on every step of a drag, so an app that pauses while scrubbing calls `pause()` many times over one gesture — and every one of them after the first was announced as a state change. Only the pause that actually stops playback is reported now, which is what Android already did.

`stop()` is unchanged and still reports `paused` whatever was happening, since clearing the playlist is a change either way.

The behaviour table in the README carried the same confusion: it listed `pause` → `paused` and `seekTo` → `playing` without saying that both are conditional. Both rows now say when the event is reported, matching the rule the table's own introduction already stated.
