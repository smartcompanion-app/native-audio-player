package app.smartcompanion.audio;

import android.Manifest;
import android.content.ComponentName;
import android.content.Context;
import android.os.Bundle;
import android.util.Log;
import androidx.annotation.Nullable;
import androidx.core.content.ContextCompat;
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
import java.util.List;
import java.util.Objects;

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
                JSObject json = nativeAudioPlayer.prepareUpdateEvent("skip", mediaItem);
                controller.pause();
                notifyListeners("update", json);
            } catch (Exception e) {
                Log.e("NATIVE_AUDIO_PLAYER", "Could not trigger skip event: " + e.getMessage());
            }
        }

        @Override
        public void onIsPlayingChanged(boolean isPlaying) {
            try {
                JSObject json = nativeAudioPlayer.prepareUpdateEvent(
                    isPlaying ? "playing" : "paused",
                    Objects.requireNonNull(mediaController.getCurrentMediaItem())
                );
                notifyListeners("update", json);
            } catch (Exception e) {
                Log.e("NATIVE_AUDIO_PLAYER", "Could not trigger play/pause event: " + e.getMessage());
            }
        }

        @Override
        public void onPlaybackStateChanged(int playbackState) {
            Player.Listener.super.onPlaybackStateChanged(playbackState);

            if (playbackState == Player.STATE_ENDED) {
                try {
                    JSObject json = nativeAudioPlayer.prepareUpdateEvent(
                        "completed",
                        Objects.requireNonNull(mediaController.getCurrentMediaItem())
                    );
                    notifyListeners("update", json);
                } catch (Exception e) {
                    Log.e("NATIVE_AUDIO_PLAYER", "Could not trigger ended event: " + e.getMessage());
                }
            }
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
            () -> {
                try {
                    mediaController = controllerFuture.get();
                    //mediaController.setRepeatMode(Player.REPEAT_MODE_OFF);
                    mediaController.setMediaItems(mediaItems);

                    registerPlayerEvents();
                    call.resolve(nativeAudioPlayer.prepareIdItem(Objects.requireNonNull(mediaController.getCurrentMediaItem())));
                } catch (Exception e) {
                    Log.e("NATIVE_AUDIO_PLAYER", "Could not create media player: " + e.getMessage());
                    call.reject("Could not create media player");
                }
            },
            // MediaController is main thread only, and directExecutor() would run
            // this on whichever thread happened to complete the future
            ContextCompat.getMainExecutor(context)
        );
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
    public void setEarpiece(PluginCall call) {
        if (mediaController != null) {
            Bundle bundle = new Bundle();
            bundle.putString("CHANNEL", "earpiece");
            mediaController.sendCustomCommand(new SessionCommand("CHANNEL", bundle), bundle);
        }
        call.resolve();
    }

    @PluginMethod
    public void setSpeaker(PluginCall call) {
        if (mediaController != null) {
            Bundle bundle = new Bundle();
            bundle.putString("CHANNEL", "speaker");
            mediaController.sendCustomCommand(new SessionCommand("CHANNEL", bundle), bundle);
        }
        call.resolve();
    }

    /**
     * Resolves with the id of the item the controller is on, matching the
     * {id: string} the TypeScript definitions promise for these methods.
     */
    protected void resolveWithCurrentId(PluginCall call) {
        MediaItem mediaItem = mediaController != null ? mediaController.getCurrentMediaItem() : null;

        if (mediaItem == null) {
            call.resolve();
            return;
        }

        try {
            call.resolve(nativeAudioPlayer.prepareIdItem(mediaItem));
        } catch (Exception e) {
            Log.e("NATIVE_AUDIO_PLAYER", "Could not read the current item id: " + e.getMessage());
            call.resolve();
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
    }

    protected void unregisterPlayerEvents() {
        if (mediaController != null) {
            mediaController.removeListener(this.playerListener);
        }
    }
}
