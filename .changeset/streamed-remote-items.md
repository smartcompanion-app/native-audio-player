---
'@smartcompanion/native-audio-player': minor
---

Play remote items: `audioUri` and `imageUri` take an `http(s)` URL on every platform, and the audio is streamed from where it is instead of having to be downloaded first. `start()`, `next()`, `previous()` and `select()` now answer once the item can be played -- so its duration is known -- and reject when it cannot be loaded. On iOS the player moves from `AVAudioPlayer` to `AVPlayer`, and switching between earpiece and speaker no longer reloads the item.
