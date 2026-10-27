---
'@smartcompanion/native-audio-player': minor
---

Add `getState()`, which answers what the player is doing right now: `{ id, state, position, duration }`, with `state` being `playing`, `paused` or `stopped`. Until now the state could only be followed through the `audioPlayerChange` event, so an app that mounted after the player was started, or that missed an event, had no way to recover it. Before `start()` and after `stop()` it resolves with `stopped`, an empty `id` and zero for both times rather than rejecting.

On Android the first item is now prepared as soon as `start()` resolves, so `getDuration()` (and the `duration` from `getState()`) reports the item's length straight away instead of 0 until the first `play()` — the way iOS and the web already did.
