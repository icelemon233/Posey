package com.posey.camera;

import android.Manifest;
import android.content.ContentValues;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.PermissionState;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

import java.io.OutputStream;

@CapacitorPlugin(
    name = "PoseyPhoto",
    permissions = { @Permission(alias = "photos", strings = { Manifest.permission.WRITE_EXTERNAL_STORAGE }) }
)
public class PoseyPhotoPlugin extends Plugin {
    @PluginMethod
    public void savePhoto(PluginCall call) {
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P && getPermissionState("photos") != PermissionState.GRANTED) {
            requestPermissionForAlias("photos", call, "photoPermissionCallback");
            return;
        }
        savePhotoToLibrary(call);
    }

    @PermissionCallback
    private void photoPermissionCallback(PluginCall call) {
        if (getPermissionState("photos") != PermissionState.GRANTED) {
            call.reject("相册权限没打开。请到系统设置允许保存照片，然后再试一次。");
            return;
        }
        savePhotoToLibrary(call);
    }

    private void savePhotoToLibrary(PluginCall call) {
        String dataUrl = call.getString("dataUrl");
        String fileName = call.getString("fileName", "Posey.jpg");
        if (dataUrl == null || !dataUrl.contains(",")) {
            call.reject("照片数据无效，请重新拍摄");
            return;
        }

        try {
            byte[] bytes = Base64.decode(dataUrl.substring(dataUrl.indexOf(',') + 1), Base64.DEFAULT);
            ContentValues values = new ContentValues();
            values.put(MediaStore.Images.Media.DISPLAY_NAME, fileName);
            values.put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg");
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Posey");
                values.put(MediaStore.Images.Media.IS_PENDING, 1);
            }

            Uri uri = getContext().getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
            if (uri == null) throw new IllegalStateException("无法创建相册文件");
            try (OutputStream output = getContext().getContentResolver().openOutputStream(uri)) {
                if (output == null) throw new IllegalStateException("无法写入相册文件");
                output.write(bytes);
            } catch (Exception error) {
                getContext().getContentResolver().delete(uri, null, null);
                throw error;
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ContentValues completed = new ContentValues();
                completed.put(MediaStore.Images.Media.IS_PENDING, 0);
                getContext().getContentResolver().update(uri, completed, null, null);
            }

            JSObject result = new JSObject();
            result.put("saved", true);
            call.resolve(result);
        } catch (Exception error) {
            call.reject("照片没有保存成功", error);
        }
    }
}
