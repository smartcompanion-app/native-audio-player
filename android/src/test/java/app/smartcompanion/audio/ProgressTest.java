package app.smartcompanion.audio;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.robolectric.Shadows.shadowOf;

import android.os.Looper;
import androidx.media3.common.MediaItem;
import androidx.media3.session.MediaController;
import com.getcapacitor.JSObject;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

/**
 * The progress event, which reports the playhead while the audio runs. Before it the only way to
 * follow the playhead was to poll getPosition(), which every app ended up doing for itself -- see
 * the progress event in definitions.ts.
 * <p>
 * The ticks are posted to the looper the controller lives on, which under Robolectric is the main
 * looper, paused until a test advances it. That keeps the timing exact rather than slept for.
 */
@RunWith(RobolectricTestRunner.class)
public class ProgressTest {

    /** Records the events by name, since progress and audioPlayerChange both pass through here. */
    private static class RecordingPlugin extends NativeAudioPlayerPlugin {

        final List<String> names = new ArrayList<>();
        final List<JSObject> events = new ArrayList<>();

        @Override
        public void notifyListeners(String eventName, JSObject data) {
            names.add(eventName);
            events.add(data);
        }

        List<JSObject> progress() {
            List<JSObject> progress = new ArrayList<>();
            for (int i = 0; i < names.size(); i++) {
                if ("progress".equals(names.get(i))) {
                    progress.add(events.get(i));
                }
            }
            return progress;
        }
    }

    private RecordingPlugin plugin;
    private MediaController controller;

    @Before
    public void setUp() {
        plugin = new RecordingPlugin();
        controller = mock(MediaController.class);
        when(controller.getApplicationLooper()).thenReturn(Looper.getMainLooper());
        when(controller.getCurrentMediaItem()).thenReturn(new MediaItem.Builder().setMediaId("item1").build());
        when(controller.getCurrentPosition()).thenReturn(1250L);
        when(controller.getDuration()).thenReturn(5000L);
        plugin.mediaController = controller;
    }

    private void startPlaying() {
        when(controller.isPlaying()).thenReturn(true);
        plugin.playerListener.onIsPlayingChanged(true);
    }

    private void stopPlaying() {
        when(controller.isPlaying()).thenReturn(false);
        plugin.playerListener.onIsPlayingChanged(false);
    }

    private void advance(long millis) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis));
    }

    @Test
    public void testReportsThePlayheadTwiceASecondWhilePlaying() throws Exception {
        startPlaying();
        advance(1500);

        List<JSObject> progress = plugin.progress();
        Assert.assertEquals(3, progress.size());
        Assert.assertEquals("item1", progress.get(0).getString("id"));
        Assert.assertEquals(1.25, progress.get(0).getDouble("position"), 0.0001);
        Assert.assertEquals(5.0, progress.get(0).getDouble("duration"), 0.0001);
    }

    @Test
    public void testReportsAtTheConfiguredInterval() {
        plugin.progressIntervalMillis = 200;

        startPlaying();
        advance(1000);

        Assert.assertEquals(5, plugin.progress().size());
    }

    @Test
    public void testAnIntervalThatIsNotAPositiveNumberFallsBackToTheDefault() {
        Assert.assertEquals(500, NativeAudioPlayer.progressIntervalMillis(null));
        Assert.assertEquals(500, NativeAudioPlayer.progressIntervalMillis(0.0));
        Assert.assertEquals(500, NativeAudioPlayer.progressIntervalMillis(-1.0));
        Assert.assertEquals(500, NativeAudioPlayer.progressIntervalMillis(Double.NaN));
        Assert.assertEquals(250, NativeAudioPlayer.progressIntervalMillis(0.25));
    }

    @Test
    public void testReportsNothingBeforePlaybackStarts() {
        advance(1500);

        Assert.assertTrue(plugin.progress().isEmpty());
    }

    @Test
    public void testStopsReportingOncePaused() {
        startPlaying();
        advance(500);
        stopPlaying();
        int reported = plugin.progress().size();

        advance(1500);

        Assert.assertEquals(reported, plugin.progress().size());
    }

    /**
     * A tick that finds the player stopped ends the reporting by itself, so a stop that reached
     * no callback -- or reached it before isPlaying changed -- cannot leave it running.
     */
    @Test
    public void testStopsReportingWhenThePlayerStoppedUnannounced() {
        startPlaying();
        when(controller.isPlaying()).thenReturn(false);

        advance(1500);

        Assert.assertTrue(plugin.progress().isEmpty());
    }

    @Test
    public void testPlayingAgainDoesNotStartASecondTimer() {
        startPlaying();
        stopPlaying();
        startPlaying();

        advance(1500);

        Assert.assertEquals(3, plugin.progress().size());
    }

    @Test
    public void testStopsReportingOnceTheControllerIsReleased() {
        startPlaying();

        plugin.releaseController();
        advance(1500);

        Assert.assertTrue(plugin.progress().isEmpty());
    }

    @Test
    public void testAddsNothingToAudioPlayerChange() {
        startPlaying();
        plugin.names.clear();

        advance(1500);

        for (String name : plugin.names) {
            Assert.assertEquals("progress", name);
        }
    }
}
