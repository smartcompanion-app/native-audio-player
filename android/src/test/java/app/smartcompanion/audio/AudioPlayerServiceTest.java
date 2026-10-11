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
        session.release();
        player.release();
    }

    private MediaSession.ConnectionResult connect(boolean trusted) {
        MediaSession.ControllerInfo controller = MediaSession.ControllerInfo.createTestOnlyControllerInfo(
            "com.example.controller",
            /* pid= */ 0,
            /* uid= */ 0,
            MediaSession.ControllerInfo.LEGACY_CONTROLLER_VERSION,
            MediaSession.ControllerInfo.LEGACY_CONTROLLER_INTERFACE_VERSION,
            trusted,
            Bundle.EMPTY,
            /* isPackageNameVerified= */ true
        );
        return service.mediaSessionCallback.onConnect(session, controller);
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
