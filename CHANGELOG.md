# @smartcompanion/native-audio-player

## 0.5.0

### Minor Changes

- [#14](https://github.com/smartcompanion-app/native-audio-player/pull/14) [`211e397`](https://github.com/smartcompanion-app/native-audio-player/commit/211e397e883f3ff98b0c81550e8f686f5e9895e1) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Update the Android playback engine to `androidx.media3` 1.10.1, from 1.7.1 — this covers both `media3-exoplayer` and `media3-session`, so it affects playback and the notification/lock screen player.

  The plugin is now built and verified against Capacitor 8.4.2. The peer requirement is unchanged: any Capacitor 8.x release still works.

### Patch Changes

- [#14](https://github.com/smartcompanion-app/native-audio-player/pull/14) [`211e397`](https://github.com/smartcompanion-app/native-audio-player/commit/211e397e883f3ff98b0c81550e8f686f5e9895e1) Thanks [@stefanhuber](https://github.com/stefanhuber)! - Fix the repository and issues URLs in `package.json`, which pointed at a `smartcompanion-io` organisation that does not exist. This corrects the links shown on npm, and the homepage and source in the CocoaPods podspec, which are both derived from these fields.

Entries below are generated from [changesets](https://github.com/changesets/changesets) — see [CONTRIBUTING.md](CONTRIBUTING.md#changesets). Releases made before this file existed are not listed; see the [releases](https://github.com/smartcompanion-app/native-audio-player/releases) and the commit history for those.
