---
'@smartcompanion/native-audio-player': patch
---

Stop the next item being briefly audible on Android when an item plays out

The player let each item roll into the next one and undid the advance afterwards, but the
callback that undid it arrives once the next item is already being rendered, so its first
milliseconds were audible before the pause landed. It now stops at the item boundary
instead, and rewinds the item that played out so it is ready to start over.
