# Contributing

This guide provides instructions for contributing to this Capacitor plugin.

## Developing

### Local Setup

1. Fork and clone the repo.
1. Install the dependencies.

    ```shell
    npm install
    ```

1. Install SwiftLint if you're on macOS.

    ```shell
    brew install swiftlint
    ```

`npm install` also sets up a [husky](https://typicode.github.io/husky/) pre-commit hook that runs Prettier over staged files, so formatting is fixed before it can reach CI.

### Scripts

#### `npm run build`

Build the plugin web assets and generate plugin API documentation using [`@capacitor/docgen`](https://github.com/ionic-team/capacitor-docgen).

It will compile the TypeScript code from `src/` into ESM JavaScript in `dist/esm/`. These files are used in apps with bundlers when your plugin is imported.

Then, Rollup will bundle the code into a single file at `dist/plugin.js`. This file is used in apps without bundlers by including it as a script in `index.html`.

#### `npm run verify`

Build and validate the web and native projects, including the native unit tests: Robolectric on Android via `gradlew build test`, and XCTest on iOS via `scripts/test-ios.sh`.

This is useful to run in CI to verify that the plugin builds for all platforms. The iOS part needs an iPhone simulator available — the script picks a booted one if there is any, otherwise the first available iPhone, so there is nothing to configure.

#### `npm run lint` / `npm run fmt`

Check formatting and code quality, autoformat/autofix if possible.

This template is integrated with ESLint, Prettier, and SwiftLint. Using these tools is completely optional, but the [Capacitor Community](https://github.com/capacitor-community/) strives to have consistent code style and structure for easier cooperation.

> **Note**: SwiftLint is not installed by npm — the `swiftlint` package only looks for a binary on your `PATH`. CI uses whatever version ships with the GitHub runner image, so lint results can differ between your machine and CI.

## Testing

`npm run verify` covers the native unit tests — `ios/Tests/` and `android/src/test/` — but not the behavioural ones. Those live in `example/`, which is a real Capacitor app driven by [WebdriverIO](https://webdriver.io/) and [Appium](https://appium.io/). The same specs in `example/test/` run against both platforms; `APPIUM_PLATFORM` selects which.

### iOS

Requires Xcode and — because `example/wdio.conf.js` pins them — an **iPhone 16** simulator running **iOS 18.6**. Any other simulator will not be matched. Install the runtime via Xcode's *Settings → Components* if it is missing, and check what you have with `xcrun simctl list devices available`.

```shell
npm install && npm run build       # in the repo root
cd example
npm install && npm run build
npx cap sync ios
npm run build:ios
xcrun simctl boot "iPhone 16"      # or use the UDID from simctl list
npm run test:ios
```

The first run builds WebDriverAgent and takes several minutes; later runs take well under a minute.

### Android

Requires a running emulator (CI uses [`android-emulator-runner`](https://github.com/reactivecircus/android-emulator-runner) with API level 36).

```shell
npm install && npm run build       # in the repo root
cd example
npm install && npm run build
npx cap sync android
npm run build:android
npm run test:android
```

## Changesets

Any pull request that changes something users would notice needs a changeset — it is what produces the version bump and the `CHANGELOG.md` entry.

```shell
npm run changeset
```

Pick the bump type (patch for fixes, minor for new API, major for breaking changes), describe the change in a sentence or two aimed at someone using the plugin, and commit the generated file in `.changeset/` along with your work.

Changes that produce nothing observable in the published package — CI config, tests, documentation, refactoring — do not need one.

## Publishing

Releases are automated. Pushing to `main` runs the [changesets action](https://github.com/changesets/action), which collects the pending changesets into a `chore: release` pull request that bumps the version and updates `CHANGELOG.md`. Merging that pull request publishes to npm and tags the release.

That means you never run `npm publish` or bump the version by hand — merging the release pull request is the whole process. Packages are published with [npm provenance](https://docs.npmjs.com/generating-provenance-statements), which signs the tarball with a verifiable link back to the workflow run that built it.

> **Note**: The [`files`](https://docs.npmjs.com/cli/v7/configuring-npm/package-json#files) array in `package.json` specifies which files get published. If you rename files/directories or add files elsewhere, you may need to update it.
