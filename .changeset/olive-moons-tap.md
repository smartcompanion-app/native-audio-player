---
'@smartcompanion/native-audio-player': minor
---

Start on the speaker on iOS, the way Android already did. The two platforms disagreed about the built-in output a player starts on -- iOS routed to the earpiece and Android to the speaker -- so the same app was quiet and held-to-ear on one and audible across the room on the other, and `getAudioOutput()` answered differently on a fresh start with nothing connected. The speaker is the default on both now: the earpiece is what `setEarpiece()` opts into.

**This changes what an iOS app hears without calling anything.** An app that relied on the earpiece default has to call `setEarpiece()` after `start()` to keep it.

A load that fails no longer changes the configured output on iOS. The retry that used to run when the player was on the speaker flipped it to the earpiece and left it there, so the next item that did load played out of the earpiece -- harmless while the speaker was the state `setSpeaker()` opted into, and wrong once it became the default. A load that fails now reports that it failed and leaves the output alone.
