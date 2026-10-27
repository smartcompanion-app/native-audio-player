---
'@smartcompanion/native-audio-player': patch
---

Android no longer reports a `paused` and an `audioOutputChange` on every `start()`. Registering for audio device changes delivers the devices that are already connected, and the plugin took that for an output change. iOS and the web never reported anything for `start()`, and now Android doesn't either. A real output change is still reported as before.
