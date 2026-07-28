---
'@smartcompanion/native-audio-player': patch
---

Fix crashes and memory leaks in the iOS and Android players.

**iOS**

- Calling any method before `start()` no longer crashes. `stop()`, `play()`, `pause()`, `select()`, `next()`, `previous()`, `setEarpiece()` and `setSpeaker()` all read through a bounds-checked accessor instead of indexing an empty playlist, and `start({items: []})` now rejects instead of trapping.
- An item whose `imageUri` is missing or undecodable no longer crashes. The lock screen artwork is decoded up front and omitted when it cannot be loaded, rather than being force unwrapped inside a handler the system invokes on an arbitrary thread.
- The plugin is no longer leaked for the lifetime of the app. The `onCompleted` callback and the five `MPRemoteCommandCenter` handlers now capture `self` weakly, the handlers are removed on `stop()` and in `deinit`, and targets belonging to the host app or other plugins are left alone (`removeTarget(nil)` removes *every* target for a command).
- `audioUri` and `imageUri` are honored in full. Previously only the last path component survived and was re-rooted in the documents directory, which happened to work for `Directory.Data` but broke for nested paths, `Directory.Cache` and `Directory.Library`. Plain paths and `file://` URLs are both accepted, matching Android and the web implementation.

**Android**

- `stop()` now removes the player listener. It was being unregistered after the controller field had already been nulled, so the guard inside `unregisterPlayerEvents()` short circuited and the listener was never detached.
- `stop()` always answers its call. An exception used to be logged and swallowed, leaving the promise pending forever.
- A second `start()` no longer leaks the previous `MediaController` or registers a duplicate listener, which caused every `update` event to be delivered twice.
- The `MediaController` callback runs on the main thread, as `MediaController` requires, instead of on whichever thread completed the future.
- A null media item in `onMediaItemTransition` is handled properly. The `assert` that was meant to guard it is disabled at runtime on Android.
- `getPosition()` always resolves with a `value`. It previously resolved with an empty object when no controller existed, reaching JS as `undefined` where iOS and the web return `0`.
- `select()`, `next()` and `previous()` resolve with `{id}` as the TypeScript definitions declare, instead of an empty object.
