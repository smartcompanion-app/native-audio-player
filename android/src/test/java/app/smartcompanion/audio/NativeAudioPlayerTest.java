package app.smartcompanion.audio;

import androidx.media3.common.MediaItem;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Assert;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public class NativeAudioPlayerTest {

    protected NativeAudioPlayer nativeAudioPlayer = new NativeAudioPlayer();

    public JSObject getItems() throws Exception {
        JSONArray items = new JSONArray();

        JSONObject item1 = new JSONObject();
        item1
            .put("id", "item1")
            .put("title", "title item1")
            .put("subtitle", "subtitle item1")
            .put("audioUri", "http://something.com/audio1.mp3")
            .put("imageUri", "http://something.com/image1.jpg");

        JSONObject item2 = new JSONObject();
        item2
            .put("id", "item2")
            .put("title", "title item2")
            .put("subtitle", "subtitle item2")
            .put("audioUri", "http://something.com/audio2.mp3")
            .put("imageUri", "http://something.com/image2.jpg");

        items.put(item1);
        items.put(item2);

        JSONObject jsObject = new JSONObject();
        jsObject.put("items", items);

        return JSObject.fromJSONObject(jsObject);
    }

    @Test
    public void testShouldTransformJsonToMediaItems() throws Exception {
        List<MediaItem> items = nativeAudioPlayer.fromJson(getItems());

        Assert.assertEquals(2, items.size());
        Assert.assertEquals("item1", items.get(0).mediaId);
        Assert.assertEquals("title item1", items.get(0).mediaMetadata.title);
        Assert.assertEquals("item2", items.get(1).mediaId);
        Assert.assertEquals("title item2", items.get(1).mediaMetadata.title);
    }
}
