---
'@smartcompanion/native-audio-player': minor
---

Report the playback the system stops on the app's behalf. An incoming call, Siri, or another app taking the audio would stop the audio without a word, leaving an app that mirrors playback in its own UI showing a pause button for audio that was no longer running.

No new state and no new event: an interruption is reported as `paused`, which is what it is, and which every app already handles. The `audioPlayerChange` event has always promised to report a change whoever caused it — an interruption is one more cause, alongside a lock screen control, a headset button and the audio running out.

The player is not started again when the interruption ends, and nothing is reported then. That matches what an output change already does: resuming is the app's decision, made by calling `play()`.

- **iOS** observes `AVAudioSession.interruptionNotification`. The system stops the player before it delivers the notification, so `isPlaying` cannot say whether anything was interrupted — the player now tracks whether playback was asked for, and only an interruption that stopped something is reported. The lock screen is put back to offering play, and the session is reactivated when the interruption ends, without which the following `play()` moved the playhead in silence.
- **Android** hands the audio focus to media3, which stops playback when something else needs the audio. media3 would also start it again by itself once the focus came back, since a transient loss suppresses playback without withdrawing the request to play — that request is now withdrawn, so the plugin keeps to its promise not to resume on its own.

Interruptions are not reported on the web: browsers expose nothing to observe them with.
