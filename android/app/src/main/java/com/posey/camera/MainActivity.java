package com.posey.camera;

import android.os.Bundle;
import androidx.core.view.WindowCompat;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(PoseyPhotoPlugin.class);
        registerPlugin(PoseySystemBarsPlugin.class);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        super.onCreate(savedInstanceState);
        PoseySystemBarsPlugin.apply(getWindow(), true, "#fffaf2");
    }
}
