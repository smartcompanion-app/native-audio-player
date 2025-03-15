#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Define the plugin using the CAP_PLUGIN Macro, and
// each method the plugin supports using the CAP_PLUGIN_METHOD macro.
CAP_PLUGIN(NativeAudioPlayerPlugin, "NativeAudioPlayer",
           CAP_PLUGIN_METHOD(start, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(play, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(pause, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(select, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(next, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(previous, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(stop, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(seekTo, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getPosition, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getDuration, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(setEarpiece, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(setSpeaker, CAPPluginReturnPromise);
)
