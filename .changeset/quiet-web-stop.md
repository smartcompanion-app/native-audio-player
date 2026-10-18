---
'@smartcompanion/native-audio-player': patch
---

On the web, `stop()` no longer rejects with "Cannot read properties of undefined (reading 'id')" when it finds an audio element but has no current item of its own. It removes the element either way and reports `paused` only when there is an item to report it for.
