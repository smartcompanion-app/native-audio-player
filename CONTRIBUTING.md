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

Build and validate the web and native projects, including the unit tests for all three: Robolectric on Android via `gradlew build test`, XCTest on iOS via `scripts/test-ios.sh`, and Vitest in a headless browser on the web via `npm run test:web`.

This is useful to run in CI to verify that the plugin builds for all platforms. The iOS part needs an iPhone simulator available — the script picks a booted one if there is any, otherwise the first available iPhone, so there is nothing to configure.

#### `npm run test:web`

Run the web implementation's tests on their own. See [Web](#web) below.

#### `npm run lint` / `npm run fmt`

Check formatting and code quality, autoformat/autofix if possible.

This template is integrated with ESLint, Prettier, and SwiftLint. Using these tools is completely optional, but the [Capacitor Community](https://github.com/capacitor-community/) strives to have consistent code style and structure for easier cooperation.

> **Note**: SwiftLint is not installed by npm — the `swiftlint` package only looks for a binary on your `PATH`. CI uses whatever version ships with the GitHub runner image, so lint results can differ between your machine and CI.

## Testing

`npm run verify` covers the unit tests — `ios/Tests/`, `android/src/test/` and `src/test/` — but not the behavioural ones. Those live in `example/`, which is a real Capacitor app driven by [WebdriverIO](https://webdriver.io/) and [Appium](https://appium.io/). `APPIUM_PLATFORM` selects which implementation a run drives: `ios`, `browser`, or Android by default.

All three implementations answer to the same contract, the one written down in `src/definitions.ts`, so the specs are split by what they can hold all three to:

| | |
|---|---|
| `example/test/contract/` | Runs on **all three**. Goes through the example app's controls and the `audioPlayerChange` events it records in `#events`, both of which iOS, Android and the web implementation are supposed to produce identically. A divergence between platforms is a failing assertion here. |
| `example/test/native/` | Native runs only. For behaviour a browser has no equivalent of — the earpiece and speaker routing, where the browser picks its own output and always reports `external`. |

A contract test that pins down a behaviour on one platform pins it down on the other two, which is the point. Shared helpers live in `example/test/helpers.js`.

### Web

The web implementation is tested by [Vitest](https://vitest.dev/) in browser mode, which runs `src/web.ts` unchanged in headless Chromium against a real `<audio>` element. A stubbed element would only prove that `web.ts` calls it, not that the playback it promises happens — so the audio files are real ones, synthesized as blob URLs at run time by `src/test/audio-fixture.ts`.

```shell
npm install
npx playwright install chromium    # once, downloads the browser
npm run test:web                   # or test:web:watch while working
```

The browser is launched with `--autoplay-policy=no-user-gesture-required`, since the tests call `play()` directly rather than through a click. Failure screenshots land in `src/test/__screenshots__/` and are gitignored.

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

### Browser

The contract suite against the web implementation. No device and no Capacitor sync — `wdio.conf.js` starts `vite preview` over `example/dist`, which is the same bundle the native runs load out of their app package, and drives it in headless Chrome. WebdriverIO manages chromedriver itself, so there is nothing to install.

```shell
npm install && npm run build       # in the repo root
cd example
npm install && npm run build
npm run test:browser
```

Chrome is launched with `--autoplay-policy=no-user-gesture-required`: the app seeks by dispatching `input` and `change` events, which carry no user gesture, so the resume `seekTo` promises would otherwise be refused.

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

> **Note**: `npm run version` is CI's job, but if you ever run it locally to preview a release, it needs a `GITHUB_TOKEN` in the environment — the changelog generator resolves pull request and author links through the GitHub API. `GITHUB_TOKEN=$(gh auth token) npm run version` works.

`main` is protected and requires the CI checks to pass. Pull requests opened with the default `GITHUB_TOKEN` do not trigger workflows, which would leave the release pull request without checks and therefore unmergeable. To avoid that, add a `RELEASE_TOKEN` repository secret — a fine-grained personal access token scoped to this repository with *Contents: read and write* and *Pull requests: read and write*. The workflow falls back to `GITHUB_TOKEN` when it is absent, in which case the release pull request has to be merged using the administrator override.

> **Note**: The [`files`](https://docs.npmjs.com/cli/v7/configuring-npm/package-json#files) array in `package.json` specifies which files get published. If you rename files/directories or add files elsewhere, you may need to update it.
