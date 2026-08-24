package com.journeyapps.barcodescanner;

import android.content.ComponentCallbacks;
import android.content.Context;
import android.content.res.Configuration;
import android.view.WindowManager;

/**
 * Detect screen rotation without motion sensors (app store compliance).
 *
 * Uses WindowManager display rotation and configuration changes instead of
 * OrientationEventListener, which queries SensorManager.getDefaultSensor().
 */
public class RotationListener {
    private int lastRotation;

    private WindowManager windowManager;
    private RotationCallback callback;
    private Context applicationContext;

    private final ComponentCallbacks componentCallbacks = new ComponentCallbacks() {
        @Override
        public void onConfigurationChanged(Configuration newConfig) {
            notifyRotationIfChanged();
        }

        @Override
        public void onLowMemory() {
        }
    };

    public RotationListener() {
    }

    public void listen(Context context, RotationCallback callback) {
        stop();

        applicationContext = context.getApplicationContext();
        this.callback = callback;

        windowManager = (WindowManager) applicationContext
                .getSystemService(Context.WINDOW_SERVICE);

        applicationContext.registerComponentCallbacks(componentCallbacks);
        notifyRotationIfChanged();
    }

    private void notifyRotationIfChanged() {
        WindowManager localWindowManager = windowManager;
        RotationCallback localCallback = callback;
        if (localWindowManager == null || localCallback == null) {
            return;
        }

        int newRotation = localWindowManager.getDefaultDisplay().getRotation();
        if (newRotation != lastRotation) {
            lastRotation = newRotation;
            localCallback.onRotationChanged(newRotation);
        }
    }

    public void stop() {
        if (applicationContext != null) {
            applicationContext.unregisterComponentCallbacks(componentCallbacks);
        }
        applicationContext = null;
        windowManager = null;
        callback = null;
    }
}
