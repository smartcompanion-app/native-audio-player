# CLAUDE.md

Capacitor plugin for native audio playback. TypeScript API in `src/`, Swift in `ios/Sources/`, Java in `android/src/main/`, and a real Capacitor app in `example/` used for end-to-end tests.

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, the build scripts, and how to run the e2e suites — this file only covers things that are not obvious from the code.

## Constraints

**Android tooling versions track the Capacitor template.** AGP, Gradle, and the androidx pins in `android/build.gradle` follow what `@capacitor/android` builds against — see `node_modules/@capacitor/android/capacitor/build.gradle`. What matters is the major and minor: dependabot moves the AGP patch on its own and that is fine, so the two are usually a patch apart (currently 8.13.2 here against the template's 8.13.0). Newer *minor* AGP and Gradle releases exist; taking one before Capacitor does diverges from the framework. Revisit when Capacitor itself moves.

**ESLint and TypeScript are held back on purpose.** `@ionic/eslint-config@0.4.0` is the latest release and still ships `@typescript-eslint` v5 with an eslintrc-style config, which caps ESLint at 8.x and TypeScript at 5.x. Upgrading either means dropping that config and migrating to flat config first.

**Capacitor stays on the latest stable 8.x.** Version 9 is still alpha.

**Releases go through changesets.** Never bump the version in `package.json` or edit `CHANGELOG.md` by hand — both are generated. A user-visible change needs a `.changeset/*.md` file (`npm run changeset`); pushing to `main` opens a release PR, and merging it publishes.

## Gotchas

- **The README's API section is generated.** Everything between `<docgen-index>` and `</docgen-api>` comes from JSDoc comments in `src/definitions.ts` via `npm run docgen`. Edit the JSDoc, not the README. Prose outside those markers is preserved.
- **`example/` is excluded from all three linters** — see `.eslintignore`, `.prettierignore`, and `swiftlint.config.js`.
- **SwiftLint is not an npm dependency.** The `swiftlint` package only looks for a binary on `PATH`, so its version differs between local machines and CI runners, and so can the lint results.
- **`npm run verify` runs the unit tests but not the e2e ones.** The Appium specs in `example/test/` are separate and need a simulator or emulator. `verify:ios` needs a simulator too, since XCTest cannot run on a `generic/platform=iOS` destination — `scripts/test-ios.sh` resolves one at runtime instead of hardcoding a device. `verify:web` needs a chromium downloaded by `npx playwright install chromium`; CI installs it in the `test_web` job, and the macOS build job deliberately runs `npm run build` instead so it does not need one.
- **The web tests run in a real browser, not jsdom.** jsdom does not implement `HTMLMediaElement` playback at all — `play()` is a stub, `duration` is `NaN`, and `loadedmetadata`/`ended` never fire — so every interesting behaviour in `src/web.ts` would end up asserted against a mock. `src/test/` uses Vitest browser mode with real audio built at run time by `audio-fixture.ts`.
- **`example/wdio.conf.js` hardcodes iPhone 16 / iOS 18.6.** Any other simulator silently fails to match.
- **A rebuilt app does not reach the device on its own.** The example app's version code never moves, so Appium leaves whatever is already installed in place and the run tests the previous build — passing or failing against code that is no longer on disk. `enforceAppInstall` is set on both native capabilities to stop this; if an e2e result contradicts the source, check `adb shell dumpsys package com.example.plugin | grep lastUpdateTime` before believing it.
- **An iOS simulator reports `speaker` whichever output is configured.** There is no receiver to route to, so `audioOutput` answers the same for an earpiece override and a speaker one — a route assertion passes against either, and anything about which port the audio lands on has to be checked on a device.
- **Nothing observable says whether iOS audio is audible.** `AVAudioPlayer` runs its clock on an inactive session, so `isPlaying` is true and the position advances exactly as it would on an active one, and `AVAudioSession` exposes no way to read back whether it is active. Silent playback and real playback are indistinguishable from a test. Activate the session and verify by ear on a device.
- **iOS delivers an interruption after it has already stopped the player**, so `isPlaying` there reports the stop rather than what was interrupted. `NativeAudioPlayer.playWhenReady` is tracked for that question, the same role `getPlayWhenReady()` plays on Android — nothing else should be read for it.
- **media3 handles a transient audio-focus loss as playback suppression, not as `playWhenReady`.** `isPlaying` goes false but `playWhenReady` stays true and the player resumes by itself once the focus returns, so keeping to "the plugin never resumes on its own" means withdrawing the request to play — see `getPlaybackSuppressionReason()` in `onIsPlayingChanged`. A *permanent* loss does clear `playWhenReady` and needs nothing.
- **Build the example for a device into `example/ios/build`.** That path and `example/ios/App/build` are the only ones `.gitignore` and `swiftlint.config.js` know about. A `-derivedDataPath` anywhere else leaves a couple of hundred megabytes of untracked derived data in the tree and has SwiftLint lint all of it — the symptom is a lint run reporting dozens of violations across twice the usual file count.
- **`isPlaying()` is already false inside `onMediaItemTransition`.** Seeking to another item drops ExoPlayer out of `STATE_READY`, and the player updates its state before it dispatches listeners — so a callback that wants to know whether playback was running has to ask `getPlayWhenReady()`. `isPlaying()` there reports the state the pending callback is about to announce, not the one before it.
- **`example/test/contract/` runs against all three implementations**, `example/test/native/` only against iOS and Android — `APPIUM_PLATFORM` picks the target and the config decides the specs. A contract spec must not reach for anything platform-specific: the browser target has no webview context to switch to, no earpiece or speaker, and always reports `external` as its output.
- **The example app disables its controls until startup finishes** — it downloads audio files before enabling them. Tests must wait for `isEnabled()`, not just for button text, or clicks land on a disabled element and are lost.
