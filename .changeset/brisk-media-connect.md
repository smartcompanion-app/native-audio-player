---
'@smartcompanion/native-audio-player': patch
---

Update media3 to 1.11.1 on Android. It brings fixes for a crash when the notification artwork finishes loading while the app is in the background, a deadlock in the media notification, and a spurious item transition when seeking within the current item.

media3 1.11 also changed how a media session hands out access to the controllers that connect to it, and the plugin's session is adjusted for that — taking the update without the adjustment left `start()` rejecting with "Could not create media player". Access now follows media3's own line: this app and the system (the notification, the lock screen, a headset) keep full control, while another app that connects to the session can read what is playing but not control it or switch the output.
