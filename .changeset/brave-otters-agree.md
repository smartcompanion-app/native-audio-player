---
'@smartcompanion/native-audio-player': patch
---

Write down what the `audioPlayerChange` states promise, and make both platforms keep to it.

`AudioPlayerState` said only that it was "the playback state of the player", so what each state meant was whatever the two implementations happened to do, and they had drifted apart. It now documents, for each state, what triggers it, what the player is left doing, and what is left to the app -- and the generated README carries it.

Pinning it down turned up three ways the platforms disagreed about an item playing through to its end:

- **`completed` could stop firing on Android.** It was announced from `STATE_ENDED`, the state a playlist reaches when it runs out. Pausing at every item boundary means the player never gets there, so the event that apps use to advance a playlist would have gone quiet. It is now announced where the boundary is actually detected.
- **An item that played out was rewound on Android but not on iOS.** Whether a following `play()` started the item again or found nothing left to play depended on the platform. The player now rewinds on both, so `completed` always leaves the item ready to play again and the app does not have to seek.
- **Android reported the same stop twice**, as `paused` and then `completed`, where iOS reported only `completed`. One transition now reports one state.
