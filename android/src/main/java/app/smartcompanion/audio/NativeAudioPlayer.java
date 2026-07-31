package app.smartcompanion.audio;

import android.media.AudioDeviceInfo;
import android.net.Uri;
import android.util.Log;
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
            if (isExternalOutput(deviceType)) {
                return OUTPUT_EXTERNAL;
            }
        }

        return OUTPUT_EARPIECE.equals(requestedChannel) ? OUTPUT_EARPIECE : OUTPUT_SPEAKER;
    }

    public boolean isExternalOutput(int deviceType) {
        switch (deviceType) {
            case AudioDeviceInfo.TYPE_WIRED_HEADSET:
            case AudioDeviceInfo.TYPE_WIRED_HEADPHONES:
            case AudioDeviceInfo.TYPE_BLUETOOTH_SCO:
            case AudioDeviceInfo.TYPE_BLUETOOTH_A2DP:
            case AudioDeviceInfo.TYPE_USB_DEVICE:
            case AudioDeviceInfo.TYPE_USB_HEADSET:
            case AudioDeviceInfo.TYPE_USB_ACCESSORY:
            case AudioDeviceInfo.TYPE_HEARING_AID:
                return true;
            default:
                return false;
        }
    }
}
