package app.smartcompanion.audio;

import android.net.Uri;
import android.util.Log;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MediaMetadata;
import com.getcapacitor.JSObject;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

public class NativeAudioPlayer {

    public List<MediaItem> fromJson(JSObject json) {
        List<MediaItem> mediaItems = new ArrayList<>();

        try {
            JSONArray items = json.getJSONArray("items");
            for (int i = 0; i < items.length(); i++) {
                mediaItems.add(getMediaItem(items.getJSONObject(i)));
            }
        } catch (Exception e) {
            Log.e("NATIVE_AUDIO_PLAYER", "Could not transform JSON to MediaItems");
            Log.e("NATIVE_AUDIO_PLAYER", Objects.requireNonNull(e.getMessage()));
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
                    .build())
            .build();
    }

    public JSObject prepareUpdateEvent(String event, MediaItem mediaItem) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("state", event);
        json.put("id", mediaItem.mediaId);
        return JSObject.fromJSONObject(json);
    }

    public JSObject prepareIdItem(MediaItem mediaItem) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("id", mediaItem.mediaId);
        return JSObject.fromJSONObject(json);
    }

}
