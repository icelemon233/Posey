package com.posey.camera;

import android.graphics.Color;
import android.os.Build;
import android.view.Window;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "PoseySystemBars")
public class PoseySystemBarsPlugin extends Plugin {
    @PluginMethod
    public void setStyle(PluginCall call) {
        boolean darkContent = call.getBoolean("darkContent", true);
        String colorValue = call.getString("backgroundColor", "#fffaf2");

        getActivity().runOnUiThread(() -> {
            apply(getActivity().getWindow(), darkContent, colorValue);
            call.resolve(new JSObject());
        });
    }

    public static void apply(Window window, boolean darkContent, String colorValue) {
        int color;
        try {
            color = Color.parseColor(colorValue);
        } catch (IllegalArgumentException ignored) {
            color = darkContent ? Color.rgb(255, 250, 242) : Color.rgb(13, 13, 16);
        }

        window.getDecorView().setBackgroundColor(color);
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(Color.TRANSPARENT);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.setStatusBarContrastEnforced(false);
            window.setNavigationBarContrastEnforced(false);
        }

        WindowInsetsControllerCompat controller = WindowCompat.getInsetsController(window, window.getDecorView());
        controller.setAppearanceLightStatusBars(darkContent);
        controller.setAppearanceLightNavigationBars(darkContent);
    }
}
