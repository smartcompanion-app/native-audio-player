package app.smartcompanion.audio;

import static androidx.media3.test.utils.robolectric.TestPlayerRunHelper.runUntilPendingCommandsAreFullyHandled;
import static androidx.media3.test.utils.robolectric.TestPlayerRunHelper.runUntilPlayWhenReady;
import static androidx.media3.test.utils.robolectric.TestPlayerRunHelper.runUntilPlaybackState;

import android.content.Context;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.media3.test.utils.FakeClock;
import androidx.media3.test.utils.FakeMediaSource;
import androidx.media3.test.utils.FakeTimeline;
import androidx.test.core.app.ApplicationProvider;
import java.util.ArrayList;
import java.util.List;
import org.junit.After;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

/**
 * What a real ExoPlayer does at the end of a media item, rather than what a mocked controller can
 * be told to do.
 *
 * The plugin reads the item boundary from the player's callbacks: it parks there instead of
 * rolling into the next item, announces `completed` from the reason it parked for, and rewinds
 * so the item is ready to play again. Every one of those is an assumption about a callback that
 * arrives -- which mocks cannot check, because a mock only reports back whatever the test told
 * it to report.
 *
 * A FakeClock lets playback run as fast as the test can drive it, and a FakeMediaSource supplies
 * a timeline without decoding anything, so this stays in the unit test suite.
 */
@RunWith(RobolectricTestRunner.class)
public class ItemBoundaryTest {

    /** Long enough to be seekable, short enough that playing it out costs nothing. */
    private static final long ITEM_DURATION_US = 10_000_000L;

    private ExoPlayer player;
    private final List<String> callbacks = new ArrayList<>();

    @Before
    public void setUp() {
        Context context = ApplicationProvider.getApplicationContext();

        // the flag under test, set the same way AudioPlayerService#getPlayer sets it
        player = new ExoPlayer.Builder(context).setClock(new FakeClock(true)).setPauseAtEndOfMediaItems(true).build();

        player.addListener(
            new Player.Listener() {
                @Override
                public void onPlayWhenReadyChanged(boolean playWhenReady, int reason) {
                    callbacks.add("playWhenReady=" + playWhenReady + " reason=" + reason);
                }

                @Override
                public void onMediaItemTransition(@androidx.annotation.Nullable androidx.media3.common.MediaItem item, int reason) {
                    callbacks.add("transition reason=" + reason);
                }

                @Override
                public void onPositionDiscontinuity(Player.PositionInfo oldPosition, Player.PositionInfo newPosition, int reason) {
                    callbacks.add("discontinuity reason=" + reason);
                }

                @Override
                public void onPlaybackStateChanged(int playbackState) {
                    callbacks.add("state=" + playbackState);
                }
            }
        );
    }

    @After
    public void tearDown() {
        if (player != null) {
            player.release();
        }
    }

    private MediaSource item(String id) {
        Format format = new Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AAC).build();
        return new FakeMediaSource(
            new FakeTimeline(new FakeTimeline.TimelineWindowDefinition(1, id, true, false, ITEM_DURATION_US)),
            format
        );
    }

    private void playToTheEndOfTheFirstItem() throws Exception {
        player.setMediaSources(java.util.Arrays.asList(item("1"), item("2")));
        player.prepare();
        runUntilPlaybackState(player, Player.STATE_READY);

        player.play();
        runUntilPlayWhenReady(player, false);
    }

    /**
     * The whole reason the plugin does not advance on its own: an item that plays out has to stop
     * where it is, so the app decides what comes next. Rolling into the next item and stepping
     * back afterwards made its first milliseconds audible.
     */
    @Test
    public void testThePlayerParksAtTheEndOfAnItemInsteadOfAdvancing() throws Exception {
        playToTheEndOfTheFirstItem();

        Assert.assertEquals("it must not have moved on to the second item", 0, player.getCurrentMediaItemIndex());
        Assert.assertFalse(player.getPlayWhenReady());
    }

    /** The reason the plugin keys `completed` off, see NativeAudioPlayerPlugin#playerListener. */
    @Test
    public void testParkingIsReportedAsEndOfMediaItem() throws Exception {
        playToTheEndOfTheFirstItem();

        Assert.assertTrue(
            "expected a playWhenReady=false with END_OF_MEDIA_ITEM, got " + callbacks,
            callbacks.contains("playWhenReady=false reason=" + Player.PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM)
        );
    }

    /** Parking is not the playlist running out, so the state `completed` used to come from never arrives. */
    @Test
    public void testParkingDoesNotReachTheEndedState() throws Exception {
        playToTheEndOfTheFirstItem();

        Assert.assertNotEquals(Player.STATE_ENDED, player.getPlaybackState());
        Assert.assertFalse("STATE_ENDED arrived after all, got " + callbacks, callbacks.contains("state=" + Player.STATE_ENDED));
    }

    /**
     * The assumption a discarded fix rested on: that one seek raises exactly one discontinuity,
     * so a flag set beside the seek could be cleared by it. Anything else and a seek the plugin
     * made reads as one the listener made, which restarted a finished item.
     */
    @Test
    public void testOneSeekRaisesExactlyOneSeekDiscontinuity() throws Exception {
        playToTheEndOfTheFirstItem();
        callbacks.clear();

        player.seekTo(0);
        // drain what the seek causes rather than waiting for one particular callback, so a seek
        // that raises none at all is a result instead of a timeout
        runUntilPendingCommandsAreFullyHandled(player);

        long seeks = callbacks
            .stream()
            .filter((c) -> c.equals("discontinuity reason=" + Player.DISCONTINUITY_REASON_SEEK))
            .count();
        Assert.assertEquals("one seek has to raise one discontinuity, got " + callbacks, 1, seeks);
    }

    /** Rewinding a parked item has to leave it stopped -- a repeat is the player getting away from the plugin. */
    @Test
    public void testRewindingAParkedItemDoesNotStartItAgain() throws Exception {
        playToTheEndOfTheFirstItem();

        player.seekTo(0);
        runUntilPendingCommandsAreFullyHandled(player);

        Assert.assertFalse("the item started itself again after the rewind", player.getPlayWhenReady());
        Assert.assertEquals(0, player.getCurrentMediaItemIndex());
        Assert.assertEquals(0, player.getCurrentPosition());
    }

    /** C is imported for the duration constant, kept referenced so the import cannot rot unnoticed. */
    @Test
    public void testTheFakeItemHasTheDurationTheTestAssumes() throws Exception {
        player.setMediaSources(java.util.Arrays.asList(item("1"), item("2")));
        player.prepare();
        runUntilPlaybackState(player, Player.STATE_READY);

        Assert.assertNotEquals(C.TIME_UNSET, player.getDuration());
        Assert.assertEquals(ITEM_DURATION_US / 1000, player.getDuration());
    }
}
