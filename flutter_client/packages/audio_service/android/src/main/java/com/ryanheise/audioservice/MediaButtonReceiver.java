package com.ryanheise.audioservice;

import android.content.Context;
import android.content.Intent;

public class MediaButtonReceiver extends androidx.media.session.MediaButtonReceiver {
    public static final String ACTION_NOTIFICATION_DELETE = "com.ryanheise.audioservice.intent.action.ACTION_NOTIFICATION_DELETE";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent != null
                && ACTION_NOTIFICATION_DELETE.equals(intent.getAction())
                && AudioService.instance != null) {
            AudioService.instance.handleDeleteNotification();
            return;
        }
        // Only handle media buttons while playback service is active.
        // Avoid super.onReceive() which calls startForegroundService and is flagged
        // as auto-start by app store compliance scanners.
        if (intent != null && Intent.ACTION_MEDIA_BUTTON.equals(intent.getAction())) {
            if (AudioService.handleIncomingMediaButtonIntent(intent)) {
                return;
            }
            return;
        }
        super.onReceive(context, intent);
    }
}
