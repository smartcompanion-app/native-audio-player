---
'@smartcompanion/native-audio-player': patch
---

Make iOS, Android and the web keep to the behaviour overview in the README, which describes what every call promises and what it reports while doing it.

- **`seekTo()` resumes playback**, so a listener who drags the scrubber hears the audio carry on from where they dropped it rather than having to press play again. It reports `playing` when that actually started something.
- **`next()` and `previous()` wrap around the playlist** on Android as they already did on iOS and the web: the last item is followed by the first, and the first is preceded by the last. They used to stop at the ends and answer as though nothing had been asked.
- **`stop()` reports `paused`** on Android and the web, which said nothing at all when the player was already stopped.
- **An output change always reports `paused`**, so an app that mirrors the player does not have to work out whether the change interrupted anything.
- **Every device change is reported.** Swapping one bluetooth device for another used to stay silent, because the output was `external` before and after -- but it is a different device, and an app that names it has something new to say.
- **Everything that moves the player is rejected before `start()` and after `stop()`.** `pause()`, `seekTo()`, `setEarpiece()` and `setSpeaker()` join `play()` and the navigation calls in refusing rather than quietly doing nothing. `stop()` stays callable at any time, and `getPosition()` and `getDuration()` still answer 0.

On iOS the route changes the plugin causes itself are no longer mistaken for the user connecting a device. Setting the audio session category and the port override both raise the same notification as plugging in headphones, and with the pause above now unconditional, `start()`, `next()` and `select()` would have paused the playback they had just prepared.
