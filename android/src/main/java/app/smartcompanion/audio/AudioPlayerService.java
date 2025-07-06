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

        if (channel.equals("earpiece")) {
            builder.setUsage(C.USAGE_VOICE_COMMUNICATION);
        } else {
            builder.setUsage(C.USAGE_MEDIA);
        }

        return builder.build();
    }

    @SuppressLint("UnsafeOptInUsageError")
    public ExoPlayer getPlayer(String channel) {
        return new ExoPlayer.Builder(this)
            //.setPauseAtEndOfMediaItems(true)
            .setAudioAttributes(getAudioAttributes(channel), false)
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
        mediaSession = new MediaSession.Builder(this, getPlayer("speaker")).setCallback(mediaSessionCallback).build();
    }

    @Override
    public void onDestroy() {
        mediaSession.getPlayer().release();
        mediaSession.release();
        mediaSession = null;
        super.onDestroy();
    }
}
