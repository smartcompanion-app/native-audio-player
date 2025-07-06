package app.smartcompanion.audio;

import android.Manifest;
import android.content.ComponentName;
import android.content.Context;
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

@CapacitorPlugin(
    name = "NativeAudioPlayer",
    permissions = {
        @Permission(
            strings = {
                Manifest.permission.MODIFY_AUDIO_SETTINGS, Manifest.permission.FOREGROUND_SERVICE
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
            if (Player.MEDIA_ITEM_TRANSITION_REASON_AUTO == reason) {
                mediaController.pause();
                mediaController.seekToPreviousMediaItem();
            }

            try {
                assert mediaItem != null;
                JSObject json = nativeAudioPlayer.prepareUpdateEvent("skip", mediaItem);
                mediaController.pause();
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
            MoreExecutors.directExecutor()
        );
    }

    @PluginMethod
    public void stop(PluginCall call) {
        try {
            if (mediaController != null) {
                mediaController.pause();
                mediaController.stop();
                mediaController.release();
                mediaController = null;
                unregisterPlayerEvents();
            }
            if (call != null) {
                call.resolve();
            }
        } catch (Exception e) {
            Log.e("NATIVE_AUDIO_PLAYER", "Native Audio Player stop: " + e.getMessage());
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

        if (mediaController != null && id != null && mediaController.getMediaItemCount() > 0) {
            for (int i = 0; i < mediaController.getMediaItemCount(); i++) {
                MediaItem mediaItem = mediaController.getMediaItemAt(i);

                if (id.equals(mediaItem.mediaId)) {
                    mediaController.seekTo(i, 0);
                    break;
                }
            }
        }
        call.resolve();
    }

    @PluginMethod
    public void next(PluginCall call) {
        if (mediaController != null) {
            mediaController.seekToNextMediaItem();
        }
        call.resolve();
    }

    @PluginMethod
    public void previous(PluginCall call) {
        if (mediaController != null) {
            mediaController.seekToPreviousMediaItem();
        }
        call.resolve();
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
        if (mediaController != null) {
            result.put("value", mediaController.getCurrentPosition() / 1000);
        }
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

    protected void registerPlayerEvents() {
        if (mediaController != null) {
            // mediaController.removeListener(this.playerListener); // prevent double add
            mediaController.addListener(this.playerListener);
        }
    }

    protected void unregisterPlayerEvents() {
        if (mediaController != null) {
            mediaController.removeListener(this.playerListener);
        }
    }
}
