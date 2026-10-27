---
'@smartcompanion/native-audio-player': major
---

`audioPlayerChange` reports `stopped` for `stop()`, and `skipped` where it reported `skip`. `AudioPlayerState` is now `'playing' | 'paused' | 'stopped' | 'skipped' | 'completed'`, and is the one state type the plugin has.

- **`stop()` reports `stopped` instead of `paused`.** It is still reported whatever was happening, and still once: no `paused` comes alongside it for the playback it ends. A listener that handled the end of the playlist under `paused` has to handle `stopped` instead.
- **`skip` is renamed to `skipped`**, so that every state names where the player ended up. A listener comparing against `'skip'` no longer matches and has to compare against `'skipped'`.
- `getState()` resolves with an `AudioPlayerSnapshot`, whose `state` is `AudioPlayerState` without `skipped` and `completed` -- the two that describe how the player got somewhere rather than where it is.
