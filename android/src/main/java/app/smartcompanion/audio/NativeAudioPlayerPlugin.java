package app.smartcompanion.audio;

import android.Manifest;
import android.content.ComponentName;
import android.content.Context;
import android.media.AudioDeviceCallback;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.os.Bundle;
import android.os.Handler;
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

    /**
     * Answered by everything that moves the player before start() and after stop(). Acting then
     * would only promise playback that cannot happen -- see the behaviour overview in the README.
     */
    protected static final String NOT_STARTED = "could not play without a loaded audio item";

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

    /**
     * Set while a stop is being announced by whoever caused it -- an item playing out, an output
     * change, or stop() -- so the pause the player raises alongside it is not reported twice.
     */
    protected boolean pausedEventAlreadySent;

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
                // The new item is selected but not playing, so skipping away from a playing item
                // has to stop it -- and that stop is part of the skip rather than a change of
                // its own. A transition reports one state, see AudioPlayerState in
                // definitions.ts, so the paused it would otherwise raise is swallowed the way
                // the one at the end of an item is below, and only claimed when it will
                // actually arrive.
                //
                // getPlayWhenReady rather than isPlaying: seeking to another item drops the
                // player out of STATE_READY, and the state is updated before the listeners are
                // called -- so isPlaying already reads false here, reporting the change this is
                // trying to catch. playWhenReady still says whether anybody asked for playback.
                pausedEventAlreadySent = controller.getPlayWhenReady();
                controller.pause();
                notifyListeners("audioPlayerChange", json);
            } catch (Exception e) {
                Log.e("NATIVE_AUDIO_PLAYER", "Could not trigger skip event: " + e.getMessage());
            }
        }

        /**
         * Reports an item that has just played out, and rewinds it so it is ready to start over.
         *
         * The player parks at the end of the item rather than rolling into the next one,
         * see AudioPlayerService#getPlayer. Left there it sits on the last frame, where
         * play() only falls off the end again -- and END_OF_MEDIA_ITEM is the one reason
         * that tells this apart from a pause the user or the audio framework asked for.
         *
         * This is also where `completed` is announced. It used to come from STATE_ENDED, which
         * is the state for a playlist that has run out: parking at every item boundary means
         * the player never reaches it.
         */
        @Override
        public void onPlayWhenReadyChanged(boolean playWhenReady, int reason) {
            MediaController controller = mediaController;

            if (controller == null || reason != Player.PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM) {
                return;
            }

            // the pause that comes with this is the item ending rather than one anybody asked
            // for, and a transition reports one state -- so the paused event that would
            // otherwise follow is swallowed and `completed` stands on its own
            pausedEventAlreadySent = true;

            try {
                controller.seekTo(0);
                notifyListeners(
                    "audioPlayerChange",
                    nativeAudioPlayer.preparePlayerEvent("completed", Objects.requireNonNull(controller.getCurrentMediaItem()))
                );
            } catch (Exception e) {
                Log.e("NATIVE_AUDIO_PLAYER", "Could not trigger completed event: " + e.getMessage());
            }
        }

        @Override
        public void onIsPlayingChanged(boolean isPlaying) {
            // the stop at an item boundary is reported as completed, by onPlayWhenReadyChanged
            // just above -- which the player delivers before this one for the same update
            if (!isPlaying && pausedEventAlreadySent) {
                pausedEventAlreadySent = false;
                return;
            }

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
                // announced here rather than left to onIsPlayingChanged, which stays quiet when
                // there was nothing playing to stop -- and is only claimed when it will actually
                // arrive, or the flag would outlive this and swallow the next real pause
                pausedEventAlreadySent = mediaController.isPlaying();
                notifyListeners(
                    "audioPlayerChange",
                    nativeAudioPlayer.preparePlayerEvent("paused", Objects.requireNonNull(mediaController.getCurrentMediaItem()))
                );
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
        // before start() and after stop() there is nothing loaded to play -- see play() in
        // definitions.ts
        if (mediaController == null) {
            call.reject(NOT_STARTED);
            return;
        }

        mediaController.play();
        call.resolve();
    }

    @PluginMethod
    public void pause(PluginCall call) {
        if (mediaController == null) {
            call.reject(NOT_STARTED);
            return;
        }

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
                    resolveWithCurrentId(call);
                    return;
                }
            }
        }

        // an id nothing carries leaves the playlist where it was, so the caller is told rather
        // than handed back the item it already had -- see select() in definitions.ts
        call.reject("could not switch to item with given id");
    }

    @PluginMethod
    public void next(PluginCall call) {
        seekToItem(call, 1);
    }

    @PluginMethod
    public void previous(PluginCall call) {
        seekToItem(call, -1);
    }

    /**
     * Steps through the playlist and wraps around its ends, so the last item is followed by the
     * first and the first is preceded by the last.
     *
     * seekToNextMediaItem and seekToPreviousMediaItem stop at the ends unless the player repeats,
     * which would also change what happens when an item plays out.
     */
    private void seekToItem(PluginCall call, int step) {
        int count = mediaController == null ? 0 : mediaController.getMediaItemCount();

        if (count == 0) {
            call.reject("could not switch to the requested item");
            return;
        }

        int index = Math.floorMod(mediaController.getCurrentMediaItemIndex() + step, count);
        mediaController.seekTo(index, 0);
        resolveWithCurrentId(call);
    }

    @PluginMethod
    public void seekTo(PluginCall call) {
        if (mediaController == null) {
            call.reject(NOT_STARTED);
            return;
        }

        int position = call.getInt("position", 0); // position in seconds
        mediaController.seekTo(position * 1000L);

        // seeking resumes, so a listener who dragged the scrubber hears the audio carry on from
        // where they dropped it. The playing event follows from the player itself, and only when
        // this actually started something.
        mediaController.play();

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
        if (mediaController == null) {
            call.reject(NOT_STARTED);
            return;
        }

        setChannel(NativeAudioPlayer.OUTPUT_EARPIECE);
        call.resolve();
    }

    @PluginMethod
    public void setSpeaker(PluginCall call) {
        if (mediaController == null) {
            call.reject(NOT_STARTED);
            return;
        }

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

    /**
     * Reports the output the audio is on now, and stops the playback that was going somewhere
     * else.
     * <p>
     * Every device change is reported, including one that leaves the answer as it was -- swapping
     * one bluetooth device for another is still a different device, and an app that names the
     * output has something new to say about it.
     */
    protected void notifyAudioOutputChange() {
        try {
            String output = resolveAudioOutput();
            notifiedAudioOutput = output;

            // audio that was going to the earpiece must not carry on out loud once the route
            // changed, so playback stops on every output change and the app decides whether to
            // resume. The pause is announced here rather than left to onIsPlayingChanged, which
            // stays quiet when there was nothing playing to stop.
            if (mediaController != null) {
                // only a player that is playing raises onIsPlayingChanged, so claiming the event
                // otherwise leaves the flag set and swallows the next real pause
                pausedEventAlreadySent = mediaController.isPlaying();
                mediaController.pause();
                notifyListeners(
                    "audioPlayerChange",
                    nativeAudioPlayer.preparePlayerEvent("paused", Objects.requireNonNull(mediaController.getCurrentMediaItem()))
                );
            }

            notifyListeners("audioOutputChange", nativeAudioPlayer.prepareOutputEvent(output));
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

            // deliver on the looper the controller was built on rather than the main thread:
            // the callback pauses playback, and a MediaController throws when it is touched
            // from anywhere else
            Handler handler = mediaController != null ? new Handler(mediaController.getApplicationLooper()) : null;
            audioManager.registerAudioDeviceCallback(audioDeviceCallback, handler);
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
