package app.smartcompanion.audio;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.session.MediaController;
import com.getcapacitor.JSObject;
import com.getcapacitor.MessageHandler;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginResult;
import com.google.common.util.concurrent.Futures;
import java.util.List;
import org.json.JSONObject;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.robolectric.RobolectricTestRunner;

/**
 * Audio that is not on the device. media3 streams an http(s) URI on its own, so what is pinned
 * down here is the part around it: start() answers once the first item can actually be played --
 * its duration known, or its failure known -- rather than as soon as the playlist was handed over.
 * A remote item takes a moment to arrive, and until then there is no duration to report and no
 * way to tell a dead link from a slow one. See Item.audioUri and start() in definitions.ts.
 */
@RunWith(RobolectricTestRunner.class)
public class RemoteAudioTest {

    private NativeAudioPlayerPlugin plugin;
    private MessageHandler messageHandler;
    private MediaController controller;

    @Before
    public void setUp() {
        plugin = new NativeAudioPlayerPlugin();
        plugin.mediaItems = new java.util.ArrayList<>();
        messageHandler = mock(MessageHandler.class);
        controller = mock(MediaController.class);
        when(controller.getCurrentMediaItem()).thenReturn(new MediaItem.Builder().setMediaId("item1").build());
        when(controller.getPlaybackState()).thenReturn(Player.STATE_BUFFERING);
    }

    private PluginCall call() {
        return new PluginCall(messageHandler, "NativeAudioPlayer", "callback-id", "start", new JSObject());
    }

    /** The listener start() waits with, which is every listener but the plugin's own. */
    private Player.Listener readinessListener() {
        ArgumentCaptor<Player.Listener> listeners = ArgumentCaptor.forClass(Player.Listener.class);
        verify(controller, atLeastOnce()).addListener(listeners.capture());

        List<Player.Listener> added = listeners.getAllValues();
        for (Player.Listener listener : added) {
            if (listener != plugin.playerListener) {
                return listener;
            }
        }

        Assert.fail("start() added no listener to wait for the first item with");
        return null;
    }

    private void assertUnanswered(PluginCall call) {
        verify(messageHandler, never()).sendResponseMessage(
            eq(call),
            org.mockito.ArgumentMatchers.any(),
            org.mockito.ArgumentMatchers.any()
        );
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

    @Test
    public void testStartWaitsUntilTheFirstItemIsReady() throws Exception {
        PluginCall call = call();

        plugin.attachController(Futures.immediateFuture(controller), call);
        assertUnanswered(call);

        when(controller.getPlaybackState()).thenReturn(Player.STATE_READY);
        readinessListener().onPlaybackStateChanged(Player.STATE_READY);

        JSObject resolved = answer(call);
        Assert.assertNotNull("start() rejected an item that became ready", resolved);
        Assert.assertEquals("item1", resolved.getString("id"));
    }

    @Test
    public void testStartAnswersStraightAwayWhenTheFirstItemIsAlreadyReady() throws Exception {
        when(controller.getPlaybackState()).thenReturn(Player.STATE_READY);
        PluginCall call = call();

        plugin.attachController(Futures.immediateFuture(controller), call);

        Assert.assertEquals("item1", answer(call).getString("id"));
    }

    @Test
    public void testStartRejectsWhenTheFirstItemCannotBeLoaded() throws Exception {
        PluginCall call = call();
        plugin.attachController(Futures.immediateFuture(controller), call);

        readinessListener().onPlayerError(new PlaybackException("404", null, PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS));

        Assert.assertNull("start() resolved for an item that could not be loaded", answer(call));
        // nothing is loaded after all, so nothing is left behind to play
        verify(controller).release();
        Assert.assertNull(plugin.mediaController);
        Assert.assertNull(plugin.mediaItems);
    }

    @Test
    public void testStartRejectsWhenTheFirstItemHadAlreadyFailed() throws Exception {
        when(controller.getPlaybackState()).thenReturn(Player.STATE_IDLE);
        when(controller.getPlayerError()).thenReturn(new PlaybackException("404", null, PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS));
        PluginCall call = call();

        plugin.attachController(Futures.immediateFuture(controller), call);

        Assert.assertNull(answer(call));
    }

    @Test
    public void testStartStopsWaitingOnceAnswered() throws Exception {
        PluginCall call = call();
        plugin.attachController(Futures.immediateFuture(controller), call);
        Player.Listener waiting = readinessListener();

        waiting.onPlaybackStateChanged(Player.STATE_READY);

        verify(controller).removeListener(waiting);
        // a second ready -- the next item, a seek -- must not answer the call again
        waiting.onPlaybackStateChanged(Player.STATE_READY);
        answer(call);
    }

    @Test
    public void testARemoteUriIsHandedToThePlayerAsItIs() throws Exception {
        JSONObject json = new JSONObject();
        json.put("id", "remote");
        json.put("title", "Remote");
        json.put("subtitle", "Stream");
        json.put("audioUri", "https://example.com/audio/guide.mp3");
        json.put("imageUri", "https://example.com/images/guide.jpg");

        MediaItem mediaItem = new NativeAudioPlayer().getMediaItem(json);

        Assert.assertEquals("https://example.com/audio/guide.mp3", mediaItem.localConfiguration.uri.toString());
        Assert.assertEquals("https://example.com/images/guide.jpg", mediaItem.mediaMetadata.artworkUri.toString());
    }
}
