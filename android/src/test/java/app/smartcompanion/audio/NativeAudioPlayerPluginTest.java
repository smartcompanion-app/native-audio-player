package app.smartcompanion.audio;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import androidx.media3.common.MediaItem;
import androidx.media3.common.Player;
import androidx.media3.session.MediaController;
import com.getcapacitor.JSObject;
import com.getcapacitor.MessageHandler;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginResult;
import com.google.common.util.concurrent.Futures;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.robolectric.RobolectricTestRunner;

/**
 * Drives the plugin without a Bridge. Plugin#notifyListeners and PluginCall
 * resolve/reject only touch state the plugin owns, so a mocked MessageHandler
 * is enough to observe how a call was answered.
 */
@RunWith(RobolectricTestRunner.class)
public class NativeAudioPlayerPluginTest {

    private NativeAudioPlayerPlugin plugin;
    private MessageHandler messageHandler;

    @Before
    public void setUp() {
        plugin = new NativeAudioPlayerPlugin();
        messageHandler = mock(MessageHandler.class);
    }

    private PluginCall call() {
        return call(new JSObject());
    }

    private PluginCall call(JSObject data) {
        return new PluginCall(messageHandler, "NativeAudioPlayer", "callback-id", "method", data);
    }

    /**
     * Captures the events the plugin emits, the same way the iOS tests do. Overriding
     * notifyListeners keeps these free of a Bridge, which cannot be built headless.
     */
    private static class RecordingPlugin extends NativeAudioPlayerPlugin {

        final java.util.List<JSObject> events = new java.util.ArrayList<>();

        @Override
        public void notifyListeners(String eventName, JSObject data) {
            events.add(data);
        }
    }

    /**
     * A controller sitting on one of three items, which next() and previous() need in order to
     * work out where wrapping around lands.
     */
    private MediaController playlistOfThreeAt(int index, String currentId) {
        MediaController controller = controllerWithCurrentItem(currentId);
        when(controller.getMediaItemCount()).thenReturn(3);
        when(controller.getCurrentMediaItemIndex()).thenReturn(index);
        return controller;
    }

    private MediaController controllerWithCurrentItem(String id) {
        MediaController controller = mock(MediaController.class);
        when(controller.getCurrentMediaItem()).thenReturn(new MediaItem.Builder().setMediaId(id).build());
        return controller;
    }

    /**
     * Fails when a code path never resolves or rejects, which hangs the promise in
     * JS. Returns the resolved payload -- PluginResult holds it directly, the
     * {pluginId, data, ...} envelope is added later by MessageHandler.
     */
    private JSObject assertResolved(PluginCall call) throws Exception {
        ArgumentCaptor<PluginResult> success = ArgumentCaptor.forClass(PluginResult.class);
        ArgumentCaptor<PluginResult> error = ArgumentCaptor.forClass(PluginResult.class);

        verify(messageHandler).sendResponseMessage(eq(call), success.capture(), error.capture());

        Assert.assertNull("expected the call to resolve, but it rejected", error.getValue());

        PluginResult result = success.getValue();
        return result == null ? new JSObject() : new JSObject(result.toString());
    }

    private void assertRejected(PluginCall call) {
        ArgumentCaptor<PluginResult> success = ArgumentCaptor.forClass(PluginResult.class);
        ArgumentCaptor<PluginResult> error = ArgumentCaptor.forClass(PluginResult.class);

        verify(messageHandler).sendResponseMessage(eq(call), success.capture(), error.capture());

        Assert.assertNotNull("expected the call to reject", error.getValue());
    }

    // Without a controller every method has to answer its call rather than throw.

    @Test
    public void testGetPositionReportsZeroWithoutAController() throws Exception {
        PluginCall call = call();

        plugin.getPosition(call);

        // an absent key reaches JS as undefined, where iOS and web both report 0
        Assert.assertEquals(0.0, assertResolved(call).getDouble("value"), 0.0);
    }

    @Test
    public void testGetDurationReportsZeroWithoutAController() throws Exception {
        PluginCall call = call();

        plugin.getDuration(call);

        Assert.assertEquals(0.0, assertResolved(call).getDouble("value"), 0.0);
    }

    /**
     * play() is the one that rejects: resolving used to promise playback that could not
     * happen. See play() in definitions.ts.
     */
    @Test
    public void testPlayWithoutAControllerRejects() {
        PluginCall call = call();

        plugin.play(call);

        assertRejected(call);
    }

    @Test
    public void testPauseAndSeekRejectWithoutAController() {
        PluginCall pauseCall = call();
        plugin.pause(pauseCall);
        assertRejected(pauseCall);

        setUp();
        PluginCall seekCall = call();
        plugin.seekTo(seekCall);
        assertRejected(seekCall);

        setUp();
        PluginCall earpieceCall = call();
        plugin.setEarpiece(earpieceCall);
        assertRejected(earpieceCall);

        setUp();
        PluginCall speakerCall = call();
        plugin.setSpeaker(speakerCall);
        assertRejected(speakerCall);
    }

    @Test
    public void testSelectRejectsAnUnknownId() {
        MediaController controller = controllerWithCurrentItem("item1");
        when(controller.getMediaItemCount()).thenReturn(1);
        when(controller.getMediaItemAt(0)).thenReturn(new MediaItem.Builder().setMediaId("item1").build());
        plugin.mediaController = controller;

        JSObject data = new JSObject();
        data.put("id", "does-not-exist");
        PluginCall call = call(data);

        plugin.select(call);

        // it used to resolve with the item the caller already had
        assertRejected(call);
        verify(controller, never()).seekTo(org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyLong());
    }

    /**
     * These three promise {id: string}, so without an item there is nothing to
     * resolve with -- they still have to answer instead of leaving JS waiting.
     */
    @Test
    public void testNavigationMethodsRejectWithoutAController() {
        PluginCall nextCall = call();
        plugin.next(nextCall);
        assertRejected(nextCall);

        setUp();
        PluginCall previousCall = call();
        plugin.previous(previousCall);
        assertRejected(previousCall);

        setUp();
        JSObject data = new JSObject();
        data.put("id", "item1");
        PluginCall selectCall = call(data);
        plugin.select(selectCall);
        assertRejected(selectCall);
    }

    @Test
    public void testStopResolvesWithoutAController() throws Exception {
        PluginCall call = call();

        plugin.stop(call);

        assertResolved(call);
    }

    @Test
    public void testStopToleratesANullCall() {
        // handleOnDestroy() calls stop(null)
        plugin.stop(null);

        verify(messageHandler, never()).sendResponseMessage(
            org.mockito.ArgumentMatchers.any(),
            org.mockito.ArgumentMatchers.any(),
            org.mockito.ArgumentMatchers.any()
        );
    }

    // stop() used to null the field before calling unregisterPlayerEvents(),
    // whose own null guard then short circuited, so the listener stayed attached.

    @Test
    public void testStopRemovesTheListenerBeforeReleasingTheController() throws Exception {
        MediaController controller = mock(MediaController.class);
        plugin.mediaController = controller;

        plugin.stop(call());

        InOrder inOrder = inOrder(controller);
        inOrder.verify(controller).removeListener(plugin.playerListener);
        inOrder.verify(controller).release();
        Assert.assertNull(plugin.mediaController);
    }

    @Test
    public void testStopClearsTheMediaItems() throws Exception {
        plugin.mediaItems = new java.util.ArrayList<>();

        plugin.stop(call());

        Assert.assertNull(plugin.mediaItems);
    }

    @Test
    public void testStopAnswersTheCallWhenTheControllerThrows() {
        MediaController controller = mock(MediaController.class);
        doThrow(new IllegalStateException("boom")).when(controller).pause();
        plugin.mediaController = controller;
        PluginCall call = call();

        plugin.stop(call);

        // the exception used to be logged and swallowed, leaving the promise pending
        assertRejected(call);
        Assert.assertNull(plugin.mediaController);
    }

    // The TypeScript definitions promise {id: string} from these three.

    @Test
    public void testNextResolvesWithTheCurrentItemId() throws Exception {
        plugin.mediaController = playlistOfThreeAt(1, "item2");
        PluginCall call = call();

        plugin.next(call);

        Assert.assertEquals("item2", assertResolved(call).getString("id"));
    }

    @Test
    public void testPreviousResolvesWithTheCurrentItemId() throws Exception {
        plugin.mediaController = playlistOfThreeAt(1, "item1");
        PluginCall call = call();

        plugin.previous(call);

        Assert.assertEquals("item1", assertResolved(call).getString("id"));
    }

    @Test
    public void testSelectSeeksToTheMatchingItemAndResolvesWithItsId() throws Exception {
        MediaController controller = controllerWithCurrentItem("item2");
        when(controller.getMediaItemCount()).thenReturn(2);
        when(controller.getMediaItemAt(0)).thenReturn(new MediaItem.Builder().setMediaId("item1").build());
        when(controller.getMediaItemAt(1)).thenReturn(new MediaItem.Builder().setMediaId("item2").build());
        plugin.mediaController = controller;

        JSObject data = new JSObject();
        data.put("id", "item2");
        PluginCall call = call(data);

        plugin.select(call);

        verify(controller).seekTo(1, 0);
        Assert.assertEquals("item2", assertResolved(call).getString("id"));
    }

    // An item that plays out parks on its last frame, where play() only falls off the
    // end again. Only the end-of-item reason may rewind: the others are pauses somebody
    // asked for, and moving the position out from under them loses the listener's place.

    @Test
    public void testAnItemThatPlaysOutIsRewound() {
        MediaController controller = mock(MediaController.class);
        plugin.mediaController = controller;

        plugin.playerListener.onPlayWhenReadyChanged(false, Player.PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM);

        verify(controller).seekTo(0);
    }

    @Test
    public void testAPauseTheUserAskedForKeepsItsPosition() {
        MediaController controller = mock(MediaController.class);
        plugin.mediaController = controller;

        plugin.playerListener.onPlayWhenReadyChanged(false, Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST);

        verify(controller, never()).seekTo(0);
    }

    @Test
    public void testAnItemThatPlaysOutWithoutAControllerIsIgnored() {
        plugin.mediaController = null;

        plugin.playerListener.onPlayWhenReadyChanged(false, Player.PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM);
    }

    // See AudioPlayerState in definitions.ts: an item that plays out reports completed, and
    // reports it alone. The player pauses itself at the boundary, and announcing that pause
    // as well would describe one transition twice.

    @Test
    public void testAnItemThatPlaysOutReportsCompleted() throws Exception {
        RecordingPlugin recording = new RecordingPlugin();
        recording.mediaController = controllerWithCurrentItem("item1");

        recording.playerListener.onPlayWhenReadyChanged(false, Player.PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM);

        Assert.assertEquals(1, recording.events.size());
        Assert.assertEquals("completed", recording.events.get(0).getString("state"));
        Assert.assertEquals("item1", recording.events.get(0).getString("id"));
    }

    @Test
    public void testAnItemThatPlaysOutDoesNotAlsoReportPaused() {
        RecordingPlugin recording = new RecordingPlugin();
        recording.mediaController = controllerWithCurrentItem("item1");

        recording.playerListener.onPlayWhenReadyChanged(false, Player.PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM);
        recording.events.clear();

        // the player raises this for the same stop, right after the one above
        recording.playerListener.onIsPlayingChanged(false);

        Assert.assertTrue("completed was followed by a paused for the same stop", recording.events.isEmpty());
    }

    @Test
    public void testAPauseTheUserAskedForIsStillReported() {
        RecordingPlugin recording = new RecordingPlugin();
        recording.mediaController = controllerWithCurrentItem("item1");

        recording.playerListener.onIsPlayingChanged(false);

        Assert.assertEquals(1, recording.events.size());
        Assert.assertEquals("paused", recording.events.get(0).getString("state"));
    }

    // A second start() used to leave the previous listener attached, so every
    // audioPlayerChange event was delivered twice.

    @Test
    public void testRegisterPlayerEventsRemovesBeforeAdding() {
        MediaController controller = mock(MediaController.class);
        plugin.mediaController = controller;

        plugin.registerPlayerEvents();

        InOrder inOrder = inOrder(controller);
        inOrder.verify(controller).removeListener(plugin.playerListener);
        inOrder.verify(controller).addListener(plugin.playerListener);
    }

    @Test
    public void testReleaseControllerUnregistersAndClearsTheController() {
        MediaController controller = mock(MediaController.class);
        plugin.mediaController = controller;

        plugin.releaseController();

        verify(controller).removeListener(plugin.playerListener);
        verify(controller).release();
        Assert.assertNull(plugin.mediaController);
    }

    @Test
    public void testAnOutputChangePausesPlayback() {
        MediaController controller = mock(MediaController.class);
        when(controller.isPlaying()).thenReturn(true);
        plugin.mediaController = controller;
        plugin.notifiedAudioOutput = "speaker";
        plugin.requestedChannel = "earpiece";

        plugin.notifyAudioOutputChange();

        // audio routed to the earpiece must not carry on through another output
        verify(controller).pause();
        Assert.assertEquals("earpiece", plugin.notifiedAudioOutput);
    }

    @Test
    public void testAnOutputChangeReportsThePauseEvenWhenNothingWasPlaying() {
        RecordingPlugin recording = new RecordingPlugin();
        MediaController controller = controllerWithCurrentItem("item1");
        when(controller.isPlaying()).thenReturn(false);
        recording.mediaController = controller;
        recording.requestedChannel = "earpiece";

        recording.notifyAudioOutputChange();

        // the app is told the player is stopped whether or not this stopped it, so a listener
        // that mirrors the state does not have to guess -- see the README behaviour overview
        Assert.assertEquals("paused", recording.events.get(0).getString("state"));
        Assert.assertEquals(2, recording.events.size());
    }

    @Test
    public void testAnOutputThatStaysTheSameIsStillReported() {
        RecordingPlugin recording = new RecordingPlugin();
        MediaController controller = controllerWithCurrentItem("item1");
        recording.mediaController = controller;
        recording.notifiedAudioOutput = "speaker";
        recording.requestedChannel = "speaker";

        recording.notifyAudioOutputChange();

        // swapping one external device for another leaves the answer at external, and the app
        // still has something new to say about it
        verify(controller).pause();
        Assert.assertEquals(2, recording.events.size());
    }

    // Java assertions are disabled at runtime on Android, so the assert this
    // replaces never guarded anything.

    // A start() that fails after the controller connected has to leave nothing
    // behind: the controller keeps its listener and its session connection alive.

    @Test
    public void testAttachControllerConfiguresTheControllerAndResolvesWithTheFirstId() throws Exception {
        MediaController controller = controllerWithCurrentItem("item1");
        plugin.mediaItems = new java.util.ArrayList<>();
        PluginCall call = call();

        plugin.attachController(Futures.immediateFuture(controller), call);

        verify(controller).setMediaItems(plugin.mediaItems);
        verify(controller).addListener(plugin.playerListener);
        Assert.assertEquals("item1", assertResolved(call).getString("id"));
    }

    @Test
    public void testAttachControllerReleasesTheControllerWhenSetupFails() {
        MediaController controller = mock(MediaController.class);
        doThrow(new IllegalStateException("boom")).when(controller).setMediaItems(org.mockito.ArgumentMatchers.any());
        plugin.mediaItems = new java.util.ArrayList<>();
        PluginCall call = call();

        plugin.attachController(Futures.immediateFuture(controller), call);

        verify(controller).release();
        Assert.assertNull(plugin.mediaController);
        Assert.assertNull(plugin.mediaItems);
        assertRejected(call);
    }

    @Test
    public void testAttachControllerRejectsWhenTheConnectionFails() {
        plugin.mediaItems = new java.util.ArrayList<>();
        PluginCall call = call();

        plugin.attachController(Futures.immediateFailedFuture(new IllegalStateException("no session")), call);

        Assert.assertNull(plugin.mediaController);
        assertRejected(call);
    }

    @Test
    public void testMediaItemTransitionToleratesANullItem() {
        plugin.mediaController = mock(MediaController.class);

        plugin.playerListener.onMediaItemTransition(null, androidx.media3.common.Player.MEDIA_ITEM_TRANSITION_REASON_SEEK);
    }

    @Test
    public void testMediaItemTransitionToleratesAMissingController() {
        plugin.playerListener.onMediaItemTransition(null, androidx.media3.common.Player.MEDIA_ITEM_TRANSITION_REASON_AUTO);
    }
}
