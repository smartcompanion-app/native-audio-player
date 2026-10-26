package app.smartcompanion.audio;

import static androidx.media3.test.utils.robolectric.TestPlayerRunHelper.runUntilPendingCommandsAreFullyHandled;
import static androidx.media3.test.utils.robolectric.TestPlayerRunHelper.runUntilPlaybackState;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.media3.session.MediaController;
import androidx.media3.test.utils.FakeClock;
import androidx.media3.test.utils.FakeMediaSource;
import androidx.media3.test.utils.FakeTimeline;
import androidx.test.core.app.ApplicationProvider;
import com.getcapacitor.JSObject;
import com.getcapacitor.MessageHandler;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginResult;
import com.google.common.util.concurrent.Futures;
import java.util.Arrays;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.robolectric.RobolectricTestRunner;

/**
 * The playback rate. Spoken word -- audio guides, narration -- is often listened to faster or
 * slower than it was recorded, see setRate in definitions.ts.
 */
@RunWith(RobolectricTestRunner.class)
public class RateTest {

    private NativeAudioPlayerPlugin plugin;
    private MessageHandler messageHandler;

    @Before
    public void setUp() {
        plugin = new NativeAudioPlayerPlugin();
        messageHandler = mock(MessageHandler.class);
    }

    private PluginCall call(JSObject data) {
        return new PluginCall(messageHandler, "NativeAudioPlayer", "callback-id", "method", data);
    }

    private PluginCall rateCall(Object value) {
        JSObject data = new JSObject();
        if (value != null) {
            data.put("value", value);
        }
        return call(data);
    }

    /** Null when the call rejected, the resolved payload otherwise. */
    private JSObject answer(PluginCall call) throws Exception {
        ArgumentCaptor<PluginResult> success = ArgumentCaptor.forClass(PluginResult.class);
        ArgumentCaptor<PluginResult> error = ArgumentCaptor.forClass(PluginResult.class);
        verify(messageHandler).sendResponseMessage(eq(call), success.capture(), error.capture());

        if (error.getValue() != null) {
            return null;
        }
        PluginResult result = success.getValue();
        return result == null ? new JSObject() : new JSObject(result.toString());
    }

    private double getRate() throws Exception {
        setUpMessageHandler();
        PluginCall call = call(new JSObject());
        plugin.getRate(call);
        return answer(call).getDouble("value");
    }

    /** A fresh handler per call, so answer() verifies exactly the one call it is asked about. */
    private void setUpMessageHandler() {
        messageHandler = mock(MessageHandler.class);
    }

    private MediaController controller() {
        MediaController controller = mock(MediaController.class);
        when(controller.getCurrentMediaItem()).thenReturn(new MediaItem.Builder().setMediaId("item1").build());
        return controller;
    }

    // MARK: the plugin

    @Test
    public void testPlaysAtNormalSpeedUntilToldOtherwise() throws Exception {
        Assert.assertEquals(1.0, getRate(), 0.0);
    }

    @Test
    public void testSetsTheRateOnThePlayerKeepingThePitch() throws Exception {
        MediaController controller = controller();
        plugin.mediaController = controller;
        PluginCall call = rateCall(1.5);

        plugin.setRate(call);

        Assert.assertNotNull("setRate(1.5) rejected", answer(call));
        // PlaybackParameters(speed) leaves the pitch at 1, which is what keeps speech listenable
        verify(controller).setPlaybackParameters(new PlaybackParameters(1.5f));
        Assert.assertEquals(1.5, getRate(), 0.0);
    }

    @Test
    public void testCanBeSetBeforeStartAndAppliesOnceTheControllerConnects() throws Exception {
        PluginCall call = rateCall(0.5);
        plugin.setRate(call);
        Assert.assertNotNull("setRate(0.5) before start rejected", answer(call));

        MediaController controller = controller();
        plugin.mediaItems = new java.util.ArrayList<>();
        setUpMessageHandler();
        plugin.attachController(Futures.immediateFuture(controller), call(new JSObject()));

        verify(controller).setPlaybackParameters(new PlaybackParameters(0.5f));
    }

    /** start() builds a fresh controller over the same session, so it hands the rate on again. */
    @Test
    public void testIsHandedToEveryControllerThatConnects() throws Exception {
        plugin.rate = 2.0f;

        MediaController controller = controller();
        plugin.mediaItems = new java.util.ArrayList<>();
        plugin.attachController(Futures.immediateFuture(controller), call(new JSObject()));

        verify(controller).setPlaybackParameters(new PlaybackParameters(2.0f));
    }

    @Test
    public void testRejectsARateOutsideTheRangeAndKeepsTheOneItHad() throws Exception {
        MediaController controller = controller();
        plugin.mediaController = controller;
        plugin.rate = 1.5f;

        for (Object value : new Object[] { 0.25, 2.5, 0, -1, null }) {
            setUpMessageHandler();
            PluginCall call = rateCall(value);
            plugin.setRate(call);
            Assert.assertNull("setRate(" + value + ") was accepted", answer(call));
        }

        verify(controller, never()).setPlaybackParameters(any());
        Assert.assertEquals(1.5, getRate(), 0.0);
    }

    @Test
    public void testAcceptsBothEndsOfTheRange() throws Exception {
        PluginCall slowest = rateCall(0.5);
        plugin.setRate(slowest);
        Assert.assertNotNull(answer(slowest));

        setUpMessageHandler();
        PluginCall fastest = rateCall(2);
        plugin.setRate(fastest);
        Assert.assertNotNull(answer(fastest));
        Assert.assertEquals(2.0, getRate(), 0.0);
    }

    // MARK: the player
    //
    // What a real ExoPlayer does with the rate, rather than what a mocked controller is told.

    private MediaSource item(String id) {
        Format format = new Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AAC).build();
        return new FakeMediaSource(new FakeTimeline(new FakeTimeline.TimelineWindowDefinition(1, id, true, false, 10_000_000L)), format);
    }

    /** The plugin sets the rate once and relies on it surviving next(), previous() and select(). */
    @Test
    public void testTheRateSurvivesAChangeOfItem() throws Exception {
        ExoPlayer player = new ExoPlayer.Builder(ApplicationProvider.getApplicationContext()).setClock(new FakeClock(true)).build();

        try {
            player.setMediaSources(Arrays.asList(item("1"), item("2")));
            player.prepare();
            runUntilPlaybackState(player, Player.STATE_READY);
            player.setPlaybackParameters(new PlaybackParameters(2.0f));

            player.seekTo(1, 0);
            runUntilPendingCommandsAreFullyHandled(player);

            Assert.assertEquals(1, player.getCurrentMediaItemIndex());
            Assert.assertEquals(2.0f, player.getPlaybackParameters().speed, 0.0f);
            Assert.assertEquals(1.0f, player.getPlaybackParameters().pitch, 0.0f);
        } finally {
            player.release();
        }
    }
}
