---
'@smartcompanion/native-audio-player': minor
---

Report the audio output and rename the player event

The `update` event is now called `audioPlayerChange`. Its payload is unchanged, so migrating
is a rename:

```diff
- NativeAudioPlayer.addListener('update', (data) => { ... });
+ NativeAudioPlayer.addListener('audioPlayerChange', (data) => { ... });
```

The audio output can now be queried with `getAudioOutput()` and observed through the new
`audioOutputChange` event, which fires both when the output is changed through `setEarpiece()`
or `setSpeaker()` and when the route changes on its own, e.g. when headphones are unplugged or
a bluetooth device connects.

The output is reported as `earpiece`, `speaker` or `external`, where `external` covers every
device that is not built into the phone. The earpiece/speaker setting does not apply while such a
device is connected, so neither of the other two values would describe what is actually heard.

On iOS, `setEarpiece()` and `setSpeaker()` no longer report a made-up `paused` state as the only
sign that the output changed. They still emit `paused`, because switching the output does pause
the player, but the output change itself is now its own event.

Playback now pauses on **every** audio output change rather than only on the ones the app asks
for, so audio meant for the earpiece cannot carry on out loud through a different output. Previously
only `setEarpiece()` and `setSpeaker()` paused, and that was a side effect rather than a decision;
plugging in headphones or losing a bluetooth connection let playback continue. A `audioPlayerChange`
event with the `paused` state accompanies the `audioOutputChange` event whenever something was
playing, and resuming is left to the app:

```typescript
await NativeAudioPlayer.addListener('audioOutputChange', async () => {
  await NativeAudioPlayer.play(); // opt back out of the pause
});
```
