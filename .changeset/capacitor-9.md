---
'@smartcompanion/native-audio-player': major
---

Support Capacitor 9. The plugin now requires Capacitor 9, iOS 16 and Android API level 26 (Android 8.0), and builds with Android Gradle Plugin 9 against compileSdk 37. The Swift package no longer depends on the Cordova product. The Android library declares its `proguard-rules.pro` as consumer rules, and the plugin is tested against an R8-minified release build. Apps that stay on Capacitor 8 should keep using version 2.x.
