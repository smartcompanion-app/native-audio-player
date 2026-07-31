package app.smartcompanion.audio;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import androidx.media3.common.MediaItem;
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
        Assert.assertEquals(0L, assertResolved(call).getLong("value"));
    }

    @Test
    public void testGetDurationReportsZeroWithoutAController() throws Exception {
        PluginCall call = call();

        plugin.getDuration(call);

        Assert.assertEquals(0L, assertResolved(call).getLong("value"));
    }

    @Test
    public void testPlaybackMethodsResolveWithoutAController() throws Exception {
        PluginCall playCall = call();
        plugin.play(playCall);
        assertResolved(playCall);

        setUp();
        PluginCall pauseCall = call();
        plugin.pause(pauseCall);
        assertResolved(pauseCall);

        setUp();
        PluginCall seekCall = call();
        plugin.seekTo(seekCall);
        assertResolved(seekCall);
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
        plugin.mediaController = controllerWithCurrentItem("item2");
        PluginCall call = call();

        plugin.next(call);

        Assert.assertEquals("item2", assertResolved(call).getString("id"));
    }

    @Test
    public void testPreviousResolvesWithTheCurrentItemId() throws Exception {
        plugin.mediaController = controllerWithCurrentItem("item1");
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
