---
'@smartcompanion/native-audio-player': patch
---

Fix the iOS lock screen and control centre transport, where every control except pause was either missing or inert.

`MPRemoteCommandCenter` is a process-wide singleton on which every command starts out enabled, so a command the plugin never handles is still a control the system is willing to draw and nothing will ever answer. The skip pair is the one that costs: while `skipForwardCommand` and `skipBackwardCommand` are enabled the transport shows the fifteen-second skip buttons in place of the track buttons, which is why next and previous could be registered, enabled, and still never reach the plugin. `start()` now disables every command it does not implement.

The play/pause button on a headset or bluetooth device now works. It sends a single toggle command rather than the separate play and pause the on-screen controls use, and that command had no handler, so the button did nothing.

The lock screen also kept its own clock, seeded with the elapsed time and advanced at the playback rate it was last handed. The rate was hardcoded to `1.0` and neither field was written again after the item loaded, so the controls described a player that was playing from the moment it loaded and never stopped: the pause button never turned back into a play button, leaving the play command unreachable, and the scrubber ran on regardless of where the audio actually was. The rate now follows the player, and `play()`, `pause()` and `seekTo()` write both fields back.
