package app.smartcompanion.audio;

import android.Manifest;
import android.content.ComponentName;
import android.content.Context;
import android.media.AudioDeviceCallback;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.os.Bundle;
import android.util.Log;
import androidx.annotation.Nullable;
import androidx.media3.common.MediaItem;
import androidx.media3.common.Player;
import androidx.media3.session.MediaController;
import androidx.media3.session.SessionCommand;
import androidx.media3.session.SessionToken;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.google.common.util.concurrent.ListenableFuture;
import com.google.common.util.concurrent.MoreExecutors;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.Future;

@CapacitorPlugin(
    name = "NativeAudioPlayer",
    permissions = {
        @Permission(
            strings = {
                Manifest.permission.MODIFY_AUDIO_SETTINGS,
                Manifest.permission.FOREGROUND_SERVICE
                //Manifest.permission.FOREGROUND_SERVICE_ME
            }
        )
    }
)
public class NativeAudioPlayerPlugin extends Plugin {

    protected NativeAudioPlayer nativeAudioPlayer = new NativeAudioPlayer();

    protected MediaController mediaController;

    protected List<MediaItem> mediaItems;

    /**
     * The channel last requested through setEarpiece/setSpeaker. The service starts its player
     * on the speaker, see {@link AudioPlayerService#onCreate()}.
     */
    protected String requestedChannel = NativeAudioPlayer.OUTPUT_SPEAKER;

    /**
     * The last output reported through the audioOutputChange event, so device changes that
     * leave the resolved output as it was stay silent.
     */
    protected String notifiedAudioOutput;

    protected Player.Listener playerListener = new Player.Listener() {
        @Override
        public void onMediaItemTransition(@Nullable MediaItem mediaItem, int reason) {
            MediaController controller = mediaController;

            // a transition can still be delivered once the controller is gone
            if (controller == null) {
                return;
            }

            if (Player.MEDIA_ITEM_TRANSITION_REASON_AUTO == reason) {
                controller.pause();
                controller.seekToPreviousMediaItem();
            }

            // Java assertions are disabled at runtime on Android, so the assert
            // this replaces never actually checked anything
            if (mediaItem == null) {
                return;
            }

            try {
                JSObject json = nativeAudioPlayer.preparePlayerEvent("skip", mediaItem);
                controller.pause();
                notifyListeners("audioPlayerChange", json);
            } catch (Exception e) {
                Log.e("NATIVE_AUDIO_PLAYER", "Could not trigger skip event: " + e.getMessage());
            }
        }

        @Override
        public void onIsPlayingChanged(boolean isPlaying) {
            try {
                JSObject json = nativeAudioPlayer.preparePlayerEvent(
                    isPlaying ? "playing" : "paused",
                    Objects.requireNonNull(mediaController.getCurrentMediaItem())
                );
                notifyListeners("audioPlayerChange", json);
            } catch (Exception e) {
                Log.e("NATIVE_AUDIO_PLAYER", "Could not trigger play/pause event: " + e.getMessage());
            }
        }

        @Override
        public void onPlaybackStateChanged(int playbackState) {
            Player.Listener.super.onPlaybackStateChanged(playbackState);

            if (playbackState == Player.STATE_ENDED) {
                try {
                    JSObject json = nativeAudioPlayer.preparePlayerEvent(
                        "completed",
                        Objects.requireNonNull(mediaController.getCurrentMediaItem())
                    );
                    notifyListeners("audioPlayerChange", json);
                } catch (Exception e) {
                    Log.e("NATIVE_AUDIO_PLAYER", "Could not trigger ended event: " + e.getMessage());
                }
            }
        }
    };

    /**
     * Catches the output changes this plugin does not cause itself, e.g. headphones being
     * unplugged or a bluetooth device connecting.
     */
    protected AudioDeviceCallback audioDeviceCallback = new AudioDeviceCallback() {
        @Override
        public void onAudioDevicesAdded(AudioDeviceInfo[] addedDevices) {
            notifyAudioOutputChange();
        }

        @Override
        public void onAudioDevicesRemoved(AudioDeviceInfo[] removedDevices) {
            notifyAudioOutputChange();
        }
    };

    @Override
    protected void handleOnDestroy() {
        this.stop(null);
    }

    @PluginMethod
    public void start(PluginCall call) {
        Context context = this.getContext();

        // without this a second start() leaks the previous controller and leaves
        // its listener attached, so every update event is delivered twice
        releaseController();

        SessionToken sessionToken = new SessionToken(context, new ComponentName(context, AudioPlayerService.class));
        ListenableFuture<MediaController> controllerFuture = new MediaController.Builder(context, sessionToken).buildAsync();

        mediaItems = nativeAudioPlayer.fromJson(call.getData());

        controllerFuture.addListener(
            () -> attachController(controllerFuture, call),
            // A MediaController may only be touched from the looper it was built on,
            // which is the "CapacitorPlugins" thread every @PluginMethod runs on, and
            // buildAsync() completes the future on that same looper. directExecutor()
            // therefore keeps us on the right thread -- handing this to the main
            // executor instead makes every controller call throw.
            MoreExecutors.directExecutor()
        );
    }

    /**
     * Hands the connected controller the playlist and answers the call. Split out of
     * the connection callback so the failure path is reachable from a test.
     */
    protected void attachController(Future<MediaController> controllerFuture, PluginCall call) {
        try {
            mediaController = controllerFuture.get();
            //mediaController.setRepeatMode(Player.REPEAT_MODE_OFF);
            mediaController.setMediaItems(mediaItems);

            registerPlayerEvents();
            call.resolve(nativeAudioPlayer.prepareIdItem(Objects.requireNonNull(mediaController.getCurrentMediaItem())));
        } catch (Exception e) {
            Log.e("NATIVE_AUDIO_PLAYER", "Could not create media player: " + e.getMessage());

            // a half configured controller must not stay assigned: it keeps its
            // listener attached and its connection to the session open
            try {
                releaseController();
            } catch (Exception releaseError) {
                Log.e("NATIVE_AUDIO_PLAYER", "Could not release the media controller: " + releaseError.getMessage());
                mediaController = null;
            }

            mediaItems = null;
            call.reject("Could not create media player");
        }
    }

    @PluginMethod
    public void stop(PluginCall call) {
        String failure = null;

        try {
            if (mediaController != null) {
                mediaController.pause();
                mediaController.stop();
            }
        } catch (Exception e) {
            Log.e("NATIVE_AUDIO_PLAYER", "Native Audio Player stop: " + e.getMessage());
            failure = "Could not stop the audio player";
        }

        // released in its own block so a failed pause/stop cannot leak the controller
        try {
            releaseController();
        } catch (Exception e) {
            Log.e("NATIVE_AUDIO_PLAYER", "Could not release the media controller: " + e.getMessage());
            mediaController = null;
            failure = "Could not stop the audio player";
        }

        mediaItems = null;

        // any exception used to be logged and swallowed, hanging the promise in JS
        if (call != null) {
            if (failure != null) {
                call.reject(failure);
            } else {
                call.resolve();
            }
        }
    }

    @PluginMethod
    public void play(PluginCall call) {
        if (mediaController != null) {
            mediaController.play();
        }
        call.resolve();
    }

    @PluginMethod
    public void pause(PluginCall call) {
        if (mediaController != null) {
            mediaController.pause();
        }
        call.resolve();
    }

    @PluginMethod
    public void select(PluginCall call) {
        String id = call.getString("id");

        if (mediaController != null && id != null) {
            for (int i = 0; i < mediaController.getMediaItemCount(); i++) {
                MediaItem mediaItem = mediaController.getMediaItemAt(i);

                if (id.equals(mediaItem.mediaId)) {
                    mediaController.seekTo(i, 0);
                    break;
                }
            }
        }

        resolveWithCurrentId(call);
    }

    @PluginMethod
    public void next(PluginCall call) {
        if (mediaController != null) {
            mediaController.seekToNextMediaItem();
        }
        resolveWithCurrentId(call);
    }

    @PluginMethod
    public void previous(PluginCall call) {
        if (mediaController != null) {
            mediaController.seekToPreviousMediaItem();
        }
        resolveWithCurrentId(call);
    }

    @PluginMethod
    public void seekTo(PluginCall call) {
        int position = call.getInt("position", 0); // position in seconds
        Log.i("NATIVE_AUDIO_PLAYER", " try to seek to position " + position);
        if (mediaController != null) {
            mediaController.seekTo(position * 1000L);
        }
        call.resolve();
    }

    @PluginMethod
    public void getPosition(PluginCall call) {
        JSObject result = new JSObject();
        // always carry a value: an absent key reaches JS as undefined, where iOS
        // and the web implementation both report 0
        result.put("value", mediaController != null ? mediaController.getCurrentPosition() / 1000 : 0);
        call.resolve(result);
    }

    @PluginMethod
    public void getDuration(PluginCall call) {
        JSObject result = new JSObject();
        if (mediaController != null && mediaController.getDuration() > 0) {
            result.put("value", mediaController.getDuration() / 1000);
        } else {
            result.put("value", 0);
        }
        call.resolve(result);
    }

    @PluginMethod
    public void getAudioOutput(PluginCall call) {
        JSObject result = new JSObject();
        result.put("output", resolveAudioOutput());
        call.resolve(result);
    }

    @PluginMethod
    public void setEarpiece(PluginCall call) {
        setChannel(NativeAudioPlayer.OUTPUT_EARPIECE);
        call.resolve();
    }

    @PluginMethod
    public void setSpeaker(PluginCall call) {
        setChannel(NativeAudioPlayer.OUTPUT_SPEAKER);
        call.resolve();
    }

    protected void setChannel(String channel) {
        requestedChannel = channel;

        if (mediaController != null) {
            Bundle bundle = new Bundle();
            bundle.putString("CHANNEL", channel);
            mediaController.sendCustomCommand(new SessionCommand("CHANNEL", bundle), bundle);
        }

        notifyAudioOutputChange();
    }

    protected String resolveAudioOutput() {
        AudioManager audioManager = getAudioManager();

        if (audioManager == null) {
            return requestedChannel;
        }

        AudioDeviceInfo[] devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS);
        int[] deviceTypes = new int[devices.length];
        for (int i = 0; i < devices.length; i++) {
            deviceTypes[i] = devices[i].getType();
        }

        return nativeAudioPlayer.resolveAudioOutput(deviceTypes, requestedChannel);
    }

    protected void notifyAudioOutputChange() {
        try {
            String output = resolveAudioOutput();

            if (!output.equals(notifiedAudioOutput)) {
                notifiedAudioOutput = output;
                notifyListeners("audioOutputChange", nativeAudioPlayer.prepareOutputEvent(output));
            }
        } catch (Exception e) {
            Log.e("NATIVE_AUDIO_PLAYER", "Could not trigger audio output event: " + e.getMessage());
        }
    }

    /**
     * Null while the plugin is not attached to a bridge yet -- Plugin#getContext dereferences
     * the bridge rather than returning null, so asking for it early throws.
     */
    protected AudioManager getAudioManager() {
        try {
            Context context = getContext();
            return context != null ? (AudioManager) context.getSystemService(Context.AUDIO_SERVICE) : null;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Resolves with the id of the item the controller is on, matching the
     * {id: string} the TypeScript definitions promise for these methods. Without a
     * current item there is no id to report, so the call is rejected rather than
     * resolved with an empty object -- that would reach JS as an undefined id. iOS
     * rejects the same three methods when it cannot switch item.
     */
    protected void resolveWithCurrentId(PluginCall call) {
        MediaItem mediaItem = mediaController != null ? mediaController.getCurrentMediaItem() : null;

        if (mediaItem == null) {
            call.reject("No audio item is loaded");
            return;
        }

        try {
            call.resolve(nativeAudioPlayer.prepareIdItem(mediaItem));
        } catch (Exception e) {
            Log.e("NATIVE_AUDIO_PLAYER", "Could not read the current item id: " + e.getMessage());
            call.reject("Could not read the current item id");
        }
    }

    protected void releaseController() {
        if (mediaController != null) {
            // unregister while the controller is still reachable -- doing this after
            // the field was nulled meant the guard below short circuited and the
            // listener was never actually removed
            unregisterPlayerEvents();
            mediaController.release();
            mediaController = null;
        }
    }

    protected void registerPlayerEvents() {
        if (mediaController != null) {
            mediaController.removeListener(this.playerListener); // prevent double add
            mediaController.addListener(this.playerListener);
        }

        AudioManager audioManager = getAudioManager();
        if (audioManager != null) {
            // seed the baseline first, the callback fires straight away with the devices
            // that are already connected and that is not a change worth reporting
            notifiedAudioOutput = resolveAudioOutput();
            audioManager.unregisterAudioDeviceCallback(audioDeviceCallback); // prevent double add
            audioManager.registerAudioDeviceCallback(audioDeviceCallback, null);
        }
    }

    protected void unregisterPlayerEvents() {
        if (mediaController != null) {
            mediaController.removeListener(this.playerListener);
        }

        AudioManager audioManager = getAudioManager();
        if (audioManager != null) {
            audioManager.unregisterAudioDeviceCallback(audioDeviceCallback);
        }
    }
}
