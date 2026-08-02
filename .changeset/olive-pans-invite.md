---
'@smartcompanion/native-audio-player': patch
---

Fix Android reporting an extra `paused` after a skip away from a playing item. `next`, `previous` and `select` stop the player so the new item is selected but not playing, and that stop was announced as a change of its own — so an app following the events saw `skip` followed by `paused` where iOS and the web implementation report only `skip`. The contract is one event per transition, which `skip` already is.
