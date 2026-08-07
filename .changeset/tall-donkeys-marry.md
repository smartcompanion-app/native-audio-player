---
'@smartcompanion/native-audio-player': major
---

First stable release.

The API in `src/definitions.ts` is settled, and what each call promises is written down rather than left to whatever the three implementations happened to do. Getting there took most of the 0.x series: the `audioPlayerChange` states now mean the same thing on iOS, Android and the web, positions and durations are fractional seconds everywhere, the lock screen and notification transports drive the same code paths an app's own calls do, and playback the system stops -- an output change, an incoming call, another app taking the audio -- is reported rather than left to desync an app's UI.

From here the version follows semver against that contract: a breaking change to it needs a major.

Nothing in this release breaks an app that was working against 0.5.0. The major is the commitment, not a migration.
