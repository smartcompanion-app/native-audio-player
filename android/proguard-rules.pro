# Consumer keep rules, applied to every app that minifies with this plugin
# (consumerProguardFiles in build.gradle). Capacitor 9 enables R8 for release builds.
#
# The plugin needs no rules of its own today:
# - NativeAudioPlayerPlugin is kept by Capacitor's core rules, which keep every
#   Plugin subclass and its @PluginMethod methods.
# - AudioPlayerService is kept because the manifest declares it.
# - media3 ships its own consumer rules.
# - Nothing else is reached by reflection, JNI or serialization.
#
# Anything added later that is found by name at runtime needs a narrow -keep here.
# Check a minified release build of the example app before relying on it.
