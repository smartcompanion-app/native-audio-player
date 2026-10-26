package app.smartcompanion.audio;

import android.os.Bundle;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.session.MediaSession;
import androidx.media3.session.SessionCommand;
import androidx.media3.session.SessionCommands;
import androidx.media3.test.utils.TestExoPlayerBuilder;
import org.junit.After;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;

/**
 * Runs the session callback against a real MediaSession rather than a mocked one: what
 * a controller may do is decided by media3's defaults, and those are what changed under
 * the plugin in media3 1.11 while every mocked test kept passing.
 */
@RunWith(RobolectricTestRunner.class)
public class AudioPlayerServiceTest {

    private static final SessionCommand CHANNEL = new SessionCommand("CHANNEL", new Bundle());

    private ExoPlayer player;
    private MediaSession session;
    private final AudioPlayerService service = new AudioPlayerService();

    @Before
    public void setUp() {
        player = new TestExoPlayerBuilder(RuntimeEnvironment.getApplication()).build();
        session = new MediaSession.Builder(RuntimeEnvironment.getApplication(), player).build();
    }

    @After
    public void tearDown() {
        if (session != null) {
            session.release();
        }
        player.release();
    }

    private MediaSession.ConnectionResult connect(boolean trusted) {
        return service.mediaSessionCallback.onConnect(session, controllerInfo(trusted));
    }

    private MediaSession.ControllerInfo controllerInfo(boolean trusted) {
        return MediaSession.ControllerInfo.createTestOnlyControllerInfo(
            "com.example.controller",
            /* pid= */ 0,
            /* uid= */ 0,
            MediaSession.ControllerInfo.LEGACY_CONTROLLER_VERSION,
            MediaSession.ControllerInfo.LEGACY_CONTROLLER_INTERFACE_VERSION,
            trusted,
            Bundle.EMPTY,
            /* isPackageNameVerified= */ true
        );
    }

    @Test
    public void testTrustedControllerCanLoadAndControlThePlaylist() {
        MediaSession.ConnectionResult result = connect(true);

        Assert.assertTrue(result.isAccepted);
        Player.Commands commands = result.availablePlayerCommands;
        // start() is setMediaItems() -- without this one it silently does nothing
        Assert.assertTrue(commands.contains(Player.COMMAND_CHANGE_MEDIA_ITEMS));
        Assert.assertTrue(commands.contains(Player.COMMAND_PLAY_PAUSE));
        Assert.assertTrue(commands.contains(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM));
        Assert.assertTrue(commands.contains(Player.COMMAND_SEEK_TO_MEDIA_ITEM));
    }

    /** setRate() is setPlaybackParameters() -- without this one it silently does nothing. */
    @Test
    public void testTrustedControllerCanChangeTheRate() {
        Assert.assertTrue(connect(true).availablePlayerCommands.contains(Player.COMMAND_SET_SPEED_AND_PITCH));
    }

    /**
     * Switching the output builds a new player and hands it the playlist and the position. The
     * rate has to go across with them, or the first output change drops the listener back to
     * normal speed.
     */
    @Test
    public void testSwitchingTheOutputKeepsTheRate() {
        // a session id has to be unique in the process, and the running service builds its own
        session.release();
        session = null;
        AudioPlayerService running = org.robolectric.Robolectric.buildService(AudioPlayerService.class).create().get();

        try {
            running.mediaSession.getPlayer().setPlaybackParameters(new androidx.media3.common.PlaybackParameters(1.5f));

            Bundle extras = new Bundle();
            extras.putString("CHANNEL", NativeAudioPlayer.OUTPUT_EARPIECE);
            running.mediaSessionCallback.onCustomCommand(running.mediaSession, controllerInfo(true), CHANNEL, extras);

            Assert.assertEquals(1.5f, running.mediaSession.getPlayer().getPlaybackParameters().speed, 0.0f);
        } finally {
            running.onDestroy();
        }
    }

    @Test
    public void testTrustedControllerCanSwitchTheOutput() {
        SessionCommands commands = connect(true).availableSessionCommands;

        Assert.assertTrue(commands.contains(CHANNEL));
    }

    @Test
    public void testUntrustedControllerCannotChangePlaybackOrOutput() {
        MediaSession.ConnectionResult result = connect(false);

        Assert.assertTrue(result.isAccepted);
        Assert.assertFalse(result.availablePlayerCommands.contains(Player.COMMAND_CHANGE_MEDIA_ITEMS));
        Assert.assertFalse(result.availablePlayerCommands.contains(Player.COMMAND_PLAY_PAUSE));
        Assert.assertFalse(result.availableSessionCommands.contains(CHANNEL));
    }
}
