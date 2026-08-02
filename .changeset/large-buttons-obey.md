---
'@smartcompanion/native-audio-player': minor
---

Report positions and durations as fractional seconds on every platform

`getPosition()` and `getDuration()` truncated to whole seconds on iOS and Android while the
web returned what the media element reported, so the same call answered differently depending
on where it ran and a progress bar could only move in jumps on the two platforms that draw one.
Both now report the fractional seconds the players already had, and `seekTo()` accepts them, so
a scrubber can hand back what it was given instead of rounding first. Callers that want whole
seconds can round the value themselves.

The iOS lock screen scrubber also stopped truncating the position it seeks to.
