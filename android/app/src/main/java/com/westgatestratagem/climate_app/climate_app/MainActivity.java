package com.westgatestratagem.climate_app.climate_app;

import android.view.WindowManager;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterFragmentActivity {

    private static final String CHANNEL = "com.cradi.screen_security/flags";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (call.method.equals("addSecureFlag")) {
                        runOnUiThread(() -> getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE));
                        result.success(null);
                    } else if (call.method.equals("clearSecureFlag")) {
                        runOnUiThread(() -> getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SECURE));
                        result.success(null);
                    } else {
                        result.notImplemented();
                    }
                });
    }
}
