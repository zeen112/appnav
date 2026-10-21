package com.mototouring.nav.media

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Android NotificationListenerService required by the OS to grant
 * the application access to MediaSessionManager.getActiveSessions().
 */
class MotoNotificationListenerService : NotificationListenerService() {
    override fun onListenerConnected() {
        super.onListenerConnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        // Notification updates can also optionally be tracked for metadata changes
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // Handled via MediaController.Callback in GlobalMediaManager
    }
}
