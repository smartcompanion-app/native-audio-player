package app.smartcompanion.audio;

import android.media.AudioDeviceInfo;
import android.net.Uri;
import android.util.Log;
import androidx.annotation.Nullable;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MediaMetadata;
import com.getcapacitor.JSObject;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public class NativeAudioPlayer {

    public static final String OUTPUT_EARPIECE = "earpiece";
    public static final String OUTPUT_SPEAKER = "speaker";
    public static final String OUTPUT_EXTERNAL = "external";

    /** How often the progress event reports by default, see StartOptions.progressInterval. */
    public static final long DEFAULT_PROGRESS_INTERVAL_MILLIS = 500;

    /**
     * What an interval start() was given turns into: anything that is not a positive number falls
     * back to the default -- see StartOptions.progressInterval in definitions.ts.
     *
     * @param seconds the interval as start() received it, or null when it was left out
     */
    public static long progressIntervalMillis(@Nullable Double seconds) {
        // NaN fails this comparison as well, so it falls back with the rest
        if (seconds == null || !(seconds > 0)) {
            return DEFAULT_PROGRESS_INTERVAL_MILLIS;
        }

        return Math.max(1, Math.round(seconds * 1000));
    }

    public List<MediaItem> fromJson(JSObject json) {
        List<MediaItem> mediaItems = new ArrayList<>();

        try {
            JSONArray items = json.getJSONArray("items");
            for (int i = 0; i < items.length(); i++) {
                mediaItems.add(getMediaItem(items.getJSONObject(i)));
            }
        } catch (Exception e) {
            // requireNonNull here used to throw straight back out of the catch block
            // whenever the underlying exception carried no message
            Log.e("NATIVE_AUDIO_PLAYER", "Could not transform JSON to MediaItems", e);
        }

        return mediaItems;
    }

    public MediaItem getMediaItem(JSONObject json) throws JSONException {
        return new MediaItem.Builder()
            .setUri(json.getString("audioUri"))
            .setMediaId(json.getString("id"))
            .setMediaMetadata(
                new MediaMetadata.Builder()
                    .setTitle(json.getString("title"))
                    .setSubtitle(json.getString("subtitle"))
                    .setArtist(json.getString("subtitle"))
                    .setArtworkUri(Uri.parse(json.getString("imageUri")))
                    .build()
            )
            .build();
    }

    public JSObject preparePlayerEvent(String event, MediaItem mediaItem) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("state", event);
        json.put("id", mediaItem.mediaId);
        return JSObject.fromJSONObject(json);
    }

    public JSObject prepareProgressEvent(MediaItem mediaItem, long positionMillis, long durationMillis) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("id", mediaItem.mediaId);
        json.put("position", positionMillis / 1000.0);
        // C.TIME_UNSET while the duration is not known yet, as in getDuration()
        json.put("duration", durationMillis > 0 ? durationMillis / 1000.0 : 0.0);
        return JSObject.fromJSONObject(json);
    }

    public JSObject prepareOutputEvent(String output) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("output", output);
        return JSObject.fromJSONObject(json);
    }

    public JSObject prepareIdItem(MediaItem mediaItem) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("id", mediaItem.mediaId);
        return JSObject.fromJSONObject(json);
    }

    /**
     * Works out which output the audio actually reaches.
     * <p>
     * The player routes by {@link androidx.media3.common.AudioAttributes} usage rather than by
     * picking a device, so the requested channel only describes the output while the audio stays
     * on the phone itself. As soon as headphones or a bluetooth device are connected the system
     * sends the audio there regardless of the usage, and neither earpiece nor speaker is true
     * any more.
     *
     * @param deviceTypes the types of the currently connected output devices
     * @param requestedChannel the channel last requested through setEarpiece/setSpeaker
     */
    public String resolveAudioOutput(int[] deviceTypes, String requestedChannel) {
        for (int deviceType : deviceTypes) {
            if (!isOnDeviceOutput(deviceType)) {
                return OUTPUT_EXTERNAL;
            }
        }

        return OUTPUT_EARPIECE.equals(requestedChannel) ? OUTPUT_EARPIECE : OUTPUT_SPEAKER;
    }

    /**
     * Whether a device type is one the phone always has, so anything else present means the
     * audio left the phone.
     * <p>
     * Listing these rather than listing the external types is deliberate. The set of external
     * types keeps growing -- LE audio, HDMI, docks, aux and USB variants -- and a missing entry
     * fails silently in the wrong direction, reporting the earpiece or speaker while the audio
     * plays somewhere else entirely. The on-device set is short and does not grow.
     * <p>
     * It is not only the two outputs the plugin switches between: getDevices() also reports
     * virtual outputs that are always there and are never a route the user hears the player
     * through, and treating those as external would pin the answer to `external` on every device.
     */
    public boolean isOnDeviceOutput(int deviceType) {
        switch (deviceType) {
            case AudioDeviceInfo.TYPE_BUILTIN_EARPIECE:
            case AudioDeviceInfo.TYPE_BUILTIN_SPEAKER:
            // the low volume speaker path, reported alongside the normal one since API 30
            case AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE:
            // the telephony network, present on every phone
            case AudioDeviceInfo.TYPE_TELEPHONY:
            // the loopback the emulator and screen recording expose
            case AudioDeviceInfo.TYPE_REMOTE_SUBMIX:
            case AudioDeviceInfo.TYPE_UNKNOWN:
                return true;
            default:
                return false;
        }
    }
}
