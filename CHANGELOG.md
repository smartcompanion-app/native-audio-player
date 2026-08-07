# @smartcompanion/native-audio-player

## 1.0.0

### Major Changes

- [#50](https://github.com/smartcompanion-app/native-audio-player/pull/50) [`037633f`](https://github.com/smartcompanion-app/native-audio-player/commit/037633f1369779b609c918917a7740e5dfead103) Thanks [@stefanhuber](https://github.com/stefanhuber)! - First stable release.

  The API in `src/definitions.ts` is settled, and what each call promises is written down rather than left to whatever the three implementations happened to do. Getting there took most of the 0.x series: the `audioPlayerChange` states now mean the same thing on iOS, Android and the web, positions and durations are fractional seconds everywhere, the lock screen and notification transports drive the same code paths an app's own calls do, and playback the system stops -- an output change, an incoming call, another app taking the audio -- is reported rather than left to desync an app's UI.

  From here the version follows semver against that contract: a breaking change to it needs a major.

  Nothing in this release breaks an app that was working against 0.5.0. The major is the commitment, not a migration.

### Minor Changes

- [#48](https://github.com/smartcompanion-app/native-audio-player/pull/48) [`2969cf8`](https://github.com/smartcompanion-app/native-audio-player/commit/2969cf8455c8c7d9e48943277dba25f5779be591) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Report the playback the system stops on the app's behalf. An incoming call, Siri, or another app taking the audio would stop the audio without a word, leaving an app that mirrors playback in its own UI showing a pause button for audio that was no longer running.

  No new state and no new event: an interruption is reported as `paused`, which is what it is, and which every app already handles. The `audioPlayerChange` event has always promised to report a change whoever caused it — an interruption is one more cause, alongside a lock screen control, a headset button and the audio running out.

  The player is not started again when the interruption ends, and nothing is reported then. That matches what an output change already does: resuming is the app's decision, made by calling `play()`.

  - **iOS** observes `AVAudioSession.interruptionNotification`. The system stops the player before it delivers the notification, so `isPlaying` cannot say whether anything was interrupted — the player now tracks whether playback was asked for, and only an interruption that stopped something is reported. The lock screen is put back to offering play, and the session is reactivated when the interruption ends, without which the following `play()` moved the playhead in silence.
  - **Android** hands the audio focus to media3, which stops playback when something else needs the audio. media3 would also start it again by itself once the focus came back, since a transient loss suppresses playback without withdrawing the request to play — that request is now withdrawn, so the plugin keeps to its promise not to resume on its own.

  Interruptions are not reported on the web: browsers expose nothing to observe them with.

- [#41](https://github.com/smartcompanion-app/native-audio-player/pull/41) [`d761637`](https://github.com/smartcompanion-app/native-audio-player/commit/d7616376b12143a8a8f671fdbfb637367b3e41b5) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Report positions and durations as fractional seconds on every platform

  `getPosition()` and `getDuration()` truncated to whole seconds on iOS and Android while the
  web returned what the media element reported, so the same call answered differently depending
  on where it ran and a progress bar could only move in jumps on the two platforms that draw one.
  Both now report the fractional seconds the players already had, and `seekTo()` accepts them, so
  a scrubber can hand back what it was given instead of rounding first. Callers that want whole
  seconds can round the value themselves.

  The iOS lock screen scrubber also stopped truncating the position it seeks to.

- [#49](https://github.com/smartcompanion-app/native-audio-player/pull/49) [`27e46c4`](https://github.com/smartcompanion-app/native-audio-player/commit/27e46c497482c8a324b1907c8fc7a5e8a3a767f3) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Start on the speaker on iOS, the way Android already did. The two platforms disagreed about the built-in output a player starts on -- iOS routed to the earpiece and Android to the speaker -- so the same app was quiet and held-to-ear on one and audible across the room on the other, and `getAudioOutput()` answered differently on a fresh start with nothing connected. The speaker is the default on both now: the earpiece is what `setEarpiece()` opts into.

  **This changes what an iOS app hears without calling anything.** An app that relied on the earpiece default has to call `setEarpiece()` after `start()` to keep it.

  A load that fails no longer changes the configured output on iOS. The retry that used to run when the player was on the speaker flipped it to the earpiece and left it there, so the next item that did load played out of the earpiece -- harmless while the speaker was the state `setSpeaker()` opted into, and wrong once it became the default. A load that fails now reports that it failed and leaves the output alone.

- [#36](https://github.com/smartcompanion-app/native-audio-player/pull/36) [`3752272`](https://github.com/smartcompanion-app/native-audio-player/commit/3752272b98d15b1508873e5e3d775f7c709178fe) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Report the audio output and rename the player event

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

### Patch Changes

- [#36](https://github.com/smartcompanion-app/native-audio-player/pull/36) [`3752272`](https://github.com/smartcompanion-app/native-audio-player/commit/3752272b98d15b1508873e5e3d775f7c709178fe) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Write down what the `audioPlayerChange` states promise, and make both platforms keep to it.

  `AudioPlayerState` said only that it was "the playback state of the player", so what each state meant was whatever the two implementations happened to do, and they had drifted apart. It now documents, for each state, what triggers it, what the player is left doing, and what is left to the app -- and the generated README carries it.

  Pinning it down turned up three ways the platforms disagreed about an item playing through to its end:

  - **`completed` could stop firing on Android.** It was announced from `STATE_ENDED`, the state a playlist reaches when it runs out. Pausing at every item boundary means the player never gets there, so the event that apps use to advance a playlist would have gone quiet. It is now announced where the boundary is actually detected.
  - **An item that played out was rewound on Android but not on iOS.** Whether a following `play()` started the item again or found nothing left to play depended on the platform. The player now rewinds on both, so `completed` always leaves the item ready to play again and the app does not have to seek.
  - **Android reported the same stop twice**, as `paused` and then `completed`, where iOS reported only `completed`. One transition now reports one state.

- [#36](https://github.com/smartcompanion-app/native-audio-player/pull/36) [`3752272`](https://github.com/smartcompanion-app/native-audio-player/commit/3752272b98d15b1508873e5e3d775f7c709178fe) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Answer three calls the way the documentation now says they answer, on iOS, Android and the web.

  - **`select()` rejects an id no item carries.** iOS and Android resolved with whatever was already selected, so a caller that asked for one item and silently got another had no way to tell. The web implementation already rejected, and is what the other two now match.
  - **`play()` rejects when there is nothing loaded**, which is the case before `start()` and after `stop()`. All three resolved, and iOS additionally announced a `playing` state with no audio behind it.
  - **`seekTo()` pulls a position outside the item to the nearest end of it.** The web and Android players already did; iOS did not keep an out-of-range position, so seeking past the end left the player somewhere it could not play from.

  An item that plays through to its end is also rewound on the web now, as it already was on iOS and Android, so `completed` leaves the item ready to play again everywhere.

- [#36](https://github.com/smartcompanion-app/native-audio-player/pull/36) [`3752272`](https://github.com/smartcompanion-app/native-audio-player/commit/3752272b98d15b1508873e5e3d775f7c709178fe) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Fix the iOS lock screen and control centre transport, where every control except pause was either missing or inert.

  `MPRemoteCommandCenter` is a process-wide singleton on which every command starts out enabled, so a command the plugin never handles is still a control the system is willing to draw and nothing will ever answer. The skip pair is the one that costs: while `skipForwardCommand` and `skipBackwardCommand` are enabled the transport shows the fifteen-second skip buttons in place of the track buttons, which is why next and previous could be registered, enabled, and still never reach the plugin. `start()` now disables every command it does not implement.

  The play/pause button on a headset or bluetooth device now works. It sends a single toggle command rather than the separate play and pause the on-screen controls use, and that command had no handler, so the button did nothing.

  The lock screen also kept its own clock, seeded with the elapsed time and advanced at the playback rate it was last handed. The rate was hardcoded to `1.0` and neither field was written again after the item loaded, so the controls described a player that was playing from the moment it loaded and never stopped: the pause button never turned back into a play button, leaving the play command unreachable, and the scrubber ran on regardless of where the audio actually was. The rate now follows the player, and `play()`, `pause()` and `seekTo()` write both fields back.

- [#36](https://github.com/smartcompanion-app/native-audio-player/pull/36) [`3752272`](https://github.com/smartcompanion-app/native-audio-player/commit/3752272b98d15b1508873e5e3d775f7c709178fe) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Stop iOS and the web implementation reporting a `paused` for a pause that stopped nothing. A scrubber fires an input event on every step of a drag, so an app that pauses while scrubbing calls `pause()` many times over one gesture — and every one of them after the first was announced as a state change. Only the pause that actually stops playback is reported now, which is what Android already did.

  `stop()` is unchanged and still reports `paused` whatever was happening, since clearing the playlist is a change either way.

  The behaviour table in the README carried the same confusion: it listed `pause` → `paused` and `seekTo` → `playing` without saying that both are conditional. Both rows now say when the event is reported, matching the rule the table's own introduction already stated.

- [#33](https://github.com/smartcompanion-app/native-audio-player/pull/33) [`b1d4853`](https://github.com/smartcompanion-app/native-audio-player/commit/b1d4853adf8c1957b5dc5cf7aa4f55f430cd9e52) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Expand the README with a quick-start usage example covering the full lifecycle: handing over a playlist with `start()`, following the `update` event, the playback and routing calls, and tearing down with `stop()`.

  Document that `audioUri` and `imageUri` have to be local file URIs on Android and iOS, including a helper that downloads a remote file into `Directory.Data`, and note that iOS resolves the file by its name in the documents directory, so files need to stay flat in that folder.

  Also record the behaviour that is not obvious from the API signatures: `start()` prepares the playlist but does not begin playback, the player emits `completed` at the end of an item instead of advancing on its own, positions and durations are whole seconds, and `setEarpiece()`/`setSpeaker()` only override the built-in output.

- [#36](https://github.com/smartcompanion-app/native-audio-player/pull/36) [`3752272`](https://github.com/smartcompanion-app/native-audio-player/commit/3752272b98d15b1508873e5e3d775f7c709178fe) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Make iOS, Android and the web keep to the behaviour overview in the README, which describes what every call promises and what it reports while doing it.

  - **`seekTo()` resumes playback**, so a listener who drags the scrubber hears the audio carry on from where they dropped it rather than having to press play again. It reports `playing` when that actually started something.
  - **`next()` and `previous()` wrap around the playlist** on Android as they already did on iOS and the web: the last item is followed by the first, and the first is preceded by the last. They used to stop at the ends and answer as though nothing had been asked.
  - **`stop()` reports `paused`** on Android and the web, which said nothing at all when the player was already stopped.
  - **An output change always reports `paused`**, so an app that mirrors the player does not have to work out whether the change interrupted anything.
  - **Every device change is reported.** Swapping one bluetooth device for another used to stay silent, because the output was `external` before and after -- but it is a different device, and an app that names it has something new to say.
  - **Everything that moves the player is rejected before `start()` and after `stop()`.** `pause()`, `seekTo()`, `setEarpiece()` and `setSpeaker()` join `play()` and the navigation calls in refusing rather than quietly doing nothing. `stop()` stays callable at any time, and `getPosition()` and `getDuration()` still answer 0.

  On iOS the route changes the plugin causes itself are no longer mistaken for the user connecting a device. Setting the audio session category and the port override both raise the same notification as plugging in headphones, and with the pause above now unconditional, `start()`, `next()` and `select()` would have paused the playback they had just prepared.

- [#36](https://github.com/smartcompanion-app/native-audio-player/pull/36) [`3752272`](https://github.com/smartcompanion-app/native-audio-player/commit/3752272b98d15b1508873e5e3d775f7c709178fe) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Fix Android reporting an extra `paused` after a skip away from a playing item. `next`, `previous` and `select` stop the player so the new item is selected but not playing, and that stop was announced as a change of its own — so an app following the events saw `skip` followed by `paused` where iOS and the web implementation report only `skip`. The contract is one event per transition, which `skip` already is.

- [#29](https://github.com/smartcompanion-app/native-audio-player/pull/29) [`417c0bd`](https://github.com/smartcompanion-app/native-audio-player/commit/417c0bdfb45153f6c36d02a1ce625cf4e2cb2830) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Fix crashes and memory leaks in the iOS and Android players.

  **iOS**

  - Calling any method before `start()` no longer crashes. `stop()`, `play()`, `pause()`, `select()`, `next()`, `previous()`, `setEarpiece()` and `setSpeaker()` all read through a bounds-checked accessor instead of indexing an empty playlist, and `start({items: []})` now rejects instead of trapping.
  - An item whose `imageUri` is missing or undecodable no longer crashes. The lock screen artwork is decoded up front and omitted when it cannot be loaded, rather than being force unwrapped inside a handler the system invokes on an arbitrary thread.
  - The plugin is no longer leaked for the lifetime of the app. The `onCompleted` callback and the five `MPRemoteCommandCenter` handlers now capture `self` weakly, the handlers are removed on `stop()`, on a failed `start()` and in `deinit`, and targets belonging to the host app or other plugins are left alone (`removeTarget(nil)` removes _every_ target for a command).
  - `audioUri` and `imageUri` are honored in full. Previously only the last path component survived and was re-rooted in the documents directory, which happened to work for `Directory.Data` but broke for nested paths, `Directory.Cache` and `Directory.Library`. Plain paths and `file://` URLs are both accepted, matching Android and the web implementation.

  **Android**

  - `stop()` now removes the player listener. It was being unregistered after the controller field had already been nulled, so the guard inside `unregisterPlayerEvents()` short circuited and the listener was never detached.
  - `stop()` always answers its call. An exception used to be logged and swallowed, leaving the promise pending forever.
  - A second `start()` no longer leaks the previous `MediaController` or registers a duplicate listener, which caused every `update` event to be delivered twice.
  - A `start()` that fails after the controller connected releases that controller instead of leaving it assigned with its listener attached.
  - A null media item in `onMediaItemTransition` is handled properly. The `assert` that was meant to guard it is disabled at runtime on Android.
  - `getPosition()` always resolves with a `value`. It previously resolved with an empty object when no controller existed, reaching JS as `undefined` where iOS and the web return `0`.
  - `select()`, `next()` and `previous()` resolve with `{id}` as the TypeScript definitions declare, instead of an empty object. When no item is loaded they reject, as they already did on iOS, rather than resolving with an `undefined` id.

- [#36](https://github.com/smartcompanion-app/native-audio-player/pull/36) [`3752272`](https://github.com/smartcompanion-app/native-audio-player/commit/3752272b98d15b1508873e5e3d775f7c709178fe) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Stop the next item being briefly audible on Android when an item plays out

  The player let each item roll into the next one and undid the advance afterwards, but the
  callback that undid it arrives once the next item is already being rendered, so its first
  milliseconds were audible before the pause landed. It now stops at the item boundary
  instead, and rewinds the item that played out so it is ready to start over.

- [#36](https://github.com/smartcompanion-app/native-audio-player/pull/36) [`3752272`](https://github.com/smartcompanion-app/native-audio-player/commit/3752272b98d15b1508873e5e3d775f7c709178fe) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Fix four things in the web implementation that the new browser test suite turned up:

  - `start()` now rejects when an audio file cannot be loaded, instead of leaving the promise pending forever. iOS and Android both already rejected.
  - `next()` and `previous()` reject before `start()` and after `stop()`, matching the other two platforms. `previous()` on an empty playlist used to leave the player on an index it could not recover from.
  - The browser's own media control now shows whether the audio is playing and keeps its scrubber in step with it, rather than sitting at "paused" on the first moment of the item for as long as it plays.
  - Pressing play, pause or seek on that control before `start()` no longer produces an unhandled promise rejection. It is still refused, just quietly.

## 0.5.0

### Minor Changes

- [#14](https://github.com/smartcompanion-app/native-audio-player/pull/14) [`211e397`](https://github.com/smartcompanion-app/native-audio-player/commit/211e397e883f3ff98b0c81550e8f686f5e9895e1) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Update the Android playback engine to `androidx.media3` 1.10.1, from 1.7.1 — this covers both `media3-exoplayer` and `media3-session`, so it affects playback and the notification/lock screen player.

  The plugin is now built and verified against Capacitor 8.4.2. The peer requirement is unchanged: any Capacitor 8.x release still works.

### Patch Changes

- [#14](https://github.com/smartcompanion-app/native-audio-player/pull/14) [`211e397`](https://github.com/smartcompanion-app/native-audio-player/commit/211e397e883f3ff98b0c81550e8f686f5e9895e1) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Fix the repository and issues URLs in `package.json`, which pointed at a `smartcompanion-io` organisation that does not exist. This corrects the links shown on npm, and the homepage and source in the CocoaPods podspec, which are both derived from these fields.

Entries below are generated from [changesets](https://github.com/changesets/changesets) — see [CONTRIBUTING.md](CONTRIBUTING.md#changesets). Releases made before this file existed are not listed; see the [releases](https://github.com/smartcompanion-app/native-audio-player/releases) and the commit history for those.
