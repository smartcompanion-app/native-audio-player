package app.smartcompanion.audio;

import android.annotation.SuppressLint;
import android.os.Bundle;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.session.MediaSession;
import androidx.media3.session.MediaSessionService;
import androidx.media3.session.SessionCommand;
import androidx.media3.session.SessionCommands;
import androidx.media3.session.SessionResult;
import com.google.common.util.concurrent.Futures;
import com.google.common.util.concurrent.ListenableFuture;
import java.util.ArrayList;
import java.util.List;

public class AudioPlayerService extends MediaSessionService {

    protected MediaSession mediaSession;

    protected MediaSession.Callback mediaSessionCallback = new MediaSession.Callback() {
        @NonNull
        @Override
        public MediaSession.ConnectionResult onConnect(@NonNull MediaSession session, @NonNull MediaSession.ControllerInfo controller) {
            MediaSession.ConnectionResult connectionResult = MediaSession.Callback.super.onConnect(session, controller);

            SessionCommands sessionCommands = connectionResult.availableSessionCommands
                .buildUpon()
                .add(new SessionCommand("CHANNEL", new Bundle()))
                .build();

            return MediaSession.ConnectionResult.accept(sessionCommands, connectionResult.availablePlayerCommands);
        }

        @NonNull
        @Override
        public ListenableFuture<SessionResult> onCustomCommand(
            MediaSession session,
            @NonNull MediaSession.ControllerInfo controller,
            @NonNull SessionCommand customCommand,
            Bundle extras
        ) {
            Log.i("NATIVE_AUDIO_PLAYER", "send custom command");
            String channel = extras.getString("CHANNEL", "speaker");

            Player oldPlayer = session.getPlayer();
            long currentPosition = oldPlayer.getCurrentPosition();
            int currentMediaItemIndex = oldPlayer.getCurrentMediaItemIndex();

            ExoPlayer newPlayer = getPlayer(channel);
            newPlayer.setMediaItems(getMediaItems());
            newPlayer.seekTo(currentMediaItemIndex, currentPosition);
            session.setPlayer(newPlayer);
            oldPlayer.release();
            oldPlayer = null;

            return Futures.immediateFuture(new SessionResult(SessionResult.RESULT_SUCCESS));
        }
    };

    public List<MediaItem> getMediaItems() {
        List<MediaItem> mediaItems = new ArrayList<>();
        for (int i = 0; i < mediaSession.getPlayer().getMediaItemCount(); i++) {
            mediaItems.add(mediaSession.getPlayer().getMediaItemAt(i));
        }
        return mediaItems;
    }

    public AudioAttributes getAudioAttributes(String channel) {
        AudioAttributes.Builder builder = new AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MUSIC);

        if (NativeAudioPlayer.OUTPUT_EARPIECE.equals(channel)) {
            builder.setUsage(C.USAGE_VOICE_COMMUNICATION);
        } else {
            builder.setUsage(C.USAGE_MEDIA);
        }

        return builder.build();
    }

    @SuppressLint("UnsafeOptInUsageError")
    public ExoPlayer getPlayer(String channel) {
        return new ExoPlayer.Builder(this)
            // stop at the boundary instead of rolling into the next item. The plugin does not
            // advance on its own -- it hands the completed item to the app and lets it decide --
            // and undoing an advance from onMediaItemTransition cannot do that quietly: the
            // callback arrives once the next item is already being rendered, so the first
            // milliseconds of it are audible before the pause lands.
            .setPauseAtEndOfMediaItems(true)
            // let media3 hold the audio focus, so an incoming call or another app taking the
            // audio stops playback instead of talking over it. What it does on the way back is
            // undone in NativeAudioPlayerPlugin#onIsPlayingChanged -- this plugin never resumes
            // on its own.
            .setAudioAttributes(getAudioAttributes(channel), true)
            // pause when the audio would fall back to the speaker on its own, e.g. when
            // headphones are unplugged. The plugin pauses on every output change anyway,
            // but this happens inside the audio framework and so beats the device callback
            // to it -- without it the first moment of playback escapes through the speaker.
            .setHandleAudioBecomingNoisy(true)
            .build();
    }

    @Nullable
    @Override
    public MediaSession onGetSession(@NonNull MediaSession.ControllerInfo controllerInfo) {
        return mediaSession;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        // the speaker is the default output, the same one NativeAudioPlayerPlugin#requestedChannel
        // starts on -- the two have to agree, or getAudioOutput() reports a channel the player
        // is not actually on
        mediaSession = new MediaSession.Builder(this, getPlayer(NativeAudioPlayer.OUTPUT_SPEAKER))
            .setCallback(mediaSessionCallback)
            .build();
    }

    @Override
    public void onDestroy() {
        mediaSession.getPlayer().release();
        mediaSession.release();
        mediaSession = null;
        super.onDestroy();
    }
}
