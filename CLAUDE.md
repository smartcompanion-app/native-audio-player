# CLAUDE.md

Capacitor plugin for native audio playback. TypeScript API in `src/`, Swift in `ios/Sources/`, Java in `android/src/main/`, and a real Capacitor app in `example/` used for end-to-end tests.

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, the build scripts, and how to run the e2e suites — this file only covers things that are not obvious from the code.

## Constraints

**Android tooling versions are frozen to the Capacitor template.** AGP (8.13.0), Gradle, and the androidx pins in `android/build.gradle` deliberately match what `@capacitor/android` builds against — see `node_modules/@capacitor/android/capacitor/build.gradle`. Newer stable AGP and Gradle releases exist; bumping them independently diverges from the framework. Revisit when Capacitor itself moves.

**ESLint and TypeScript are held back on purpose.** `@ionic/eslint-config@0.4.0` is the latest release and still ships `@typescript-eslint` v5 with an eslintrc-style config, which caps ESLint at 8.x and TypeScript at 5.x. Upgrading either means dropping that config and migrating to flat config first.

**Capacitor stays on the latest stable 8.x.** Version 9 is still alpha.

## Gotchas

- **The README's API section is generated.** Everything between `<docgen-index>` and `</docgen-api>` comes from JSDoc comments in `src/definitions.ts` via `npm run docgen`. Edit the JSDoc, not the README. Prose outside those markers is preserved.
- **`example/` is excluded from all three linters** — see `.eslintignore`, `.prettierignore`, and `swiftlint.config.js`.
- **SwiftLint is not an npm dependency.** The `swiftlint` package only looks for a binary on `PATH`, so its version differs between local machines and CI runners, and so can the lint results.
- **`npm run verify` runs the native unit tests but not the e2e ones.** The Appium specs in `example/test/` are separate and need a simulator or emulator. `verify:ios` needs a simulator too, since XCTest cannot run on a `generic/platform=iOS` destination — `scripts/test-ios.sh` resolves one at runtime instead of hardcoding a device.
- **`example/wdio.conf.js` hardcodes iPhone 16 / iOS 18.6.** Any other simulator silently fails to match.
- **The example app disables its controls until startup finishes** — it downloads audio files before enabling them. Tests must wait for `isEnabled()`, not just for button text, or clicks land on a disabled element and are lost.
