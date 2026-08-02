---
'@smartcompanion/native-audio-player': patch
---

Answer three calls the way the documentation now says they answer, on iOS, Android and the web.

- **`select()` rejects an id no item carries.** iOS and Android resolved with whatever was already selected, so a caller that asked for one item and silently got another had no way to tell. The web implementation already rejected, and is what the other two now match.
- **`play()` rejects when there is nothing loaded**, which is the case before `start()` and after `stop()`. All three resolved, and iOS additionally announced a `playing` state with no audio behind it.
- **`seekTo()` pulls a position outside the item to the nearest end of it.** The web and Android players already did; iOS did not keep an out-of-range position, so seeking past the end left the player somewhere it could not play from.

An item that plays through to its end is also rewound on the web now, as it already was on iOS and Android, so `completed` leaves the item ready to play again everywhere.
