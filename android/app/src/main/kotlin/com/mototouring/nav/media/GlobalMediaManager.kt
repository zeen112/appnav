package com.mototouring.nav.media

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Universal Global Media Controller for Android.
 * Connects to active MediaSessions (Spotify, YouTube Music, local players)
 * via NotificationListenerService permissions.
 */
class GlobalMediaManager(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val mediaSessionManager = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
    private val componentName = ComponentName(context, MotoNotificationListenerService::class.java)
    
    private var activeController: MediaController? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val controllerCallback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) {
            super.onPlaybackStateChanged(state)
            sendMediaStateUpdate()
        }

        override fun onMetadataChanged(metadata: MediaMetadata?) {
            super.onMetadataChanged(metadata)
            sendMediaStateUpdate()
        }

        override fun onSessionDestroyed() {
            super.onSessionDestroyed()
            activeController = null
            refreshActiveController()
            sendMediaStateUpdate()
        }
    }

    private val sessionsChangedListener = MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
        findAndBindPrimaryController(controllers)
    }

    fun startListening() {
        if (!hasNotificationListenerPermission()) return
        try {
            mediaSessionManager.addOnActiveSessionsChangedListener(sessionsChangedListener, componentName)
            refreshActiveController()
        } catch (e: SecurityException) {
            e.printStackTrace()
        }
    }

    fun stopListening() {
        try {
            mediaSessionManager.removeOnActiveSessionsChangedListener(sessionsChangedListener)
            activeController?.unregisterCallback(controllerCallback)
            activeController = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun hasNotificationListenerPermission(): Boolean {
        val enabledPackages = NotificationManagerCompat.getEnabledListenerPackages(context)
        return enabledPackages.contains(context.packageName)
    }

    private fun refreshActiveController() {
        if (!hasNotificationListenerPermission()) return
        try {
            val controllers = mediaSessionManager.getActiveSessions(componentName)
            findAndBindPrimaryController(controllers)
        } catch (e: SecurityException) {
            e.printStackTrace()
        }
    }

    private fun findAndBindPrimaryController(controllers: List<MediaController>?) {
        if (controllers.isNullOrEmpty()) {
            activeController?.unregisterCallback(controllerCallback)
            activeController = null
            sendMediaStateUpdate()
            return
        }

        // Prioritize currently playing session, otherwise fallback to the most recent active session
        val bestController = controllers.firstOrNull { 
            it.playbackState?.state == PlaybackState.STATE_PLAYING 
        } ?: controllers.first()

        if (activeController?.sessionToken != bestController.sessionToken) {
            activeController?.unregisterCallback(controllerCallback)
            activeController = bestController
            activeController?.registerCallback(controllerCallback, mainHandler)
        }
        sendMediaStateUpdate()
    }

    private fun sendMediaStateUpdate() {
        val sink = eventSink ?: return
        val controller = activeController

        val data = if (controller != null) {
            val metadata = controller.metadata
            val state = controller.playbackState
            val isPlaying = state?.state == PlaybackState.STATE_PLAYING

            mapOf(
                "hasActiveSession" to true,
                "packageName" to controller.packageName,
                "title" to (metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "No Title"),
                "artist" to (metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: "Unknown Artist"),
                "album" to (metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""),
                "isPlaying" to isPlaying,
                "duration" to (metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L),
                "position" to (state?.position ?: 0L),
                "playbackSpeed" to (state?.playbackSpeed ?: 1.0f)
            )
        } else {
            mapOf("hasActiveSession" to false, "isPlaying" to false)
        }

        mainHandler.post {
            sink.success(data)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isPermissionGranted" -> {
                result.success(hasNotificationListenerPermission())
            }
            "requestPermission" -> {
                val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                result.success(true)
            }
            "play" -> {
                refreshActiveController()
                activeController?.transportControls?.play()
                result.success(true)
            }
            "pause" -> {
                refreshActiveController()
                activeController?.transportControls?.pause()
                result.success(true)
            }
            "togglePlayPause" -> {
                refreshActiveController()
                val isPlaying = activeController?.playbackState?.state == PlaybackState.STATE_PLAYING
                if (isPlaying) {
                    activeController?.transportControls?.pause()
                } else {
                    activeController?.transportControls?.play()
                }
                result.success(true)
            }
            "skipToNext" -> {
                refreshActiveController()
                activeController?.transportControls?.skipToNext()
                result.success(true)
            }
            "skipToPrevious" -> {
                refreshActiveController()
                activeController?.transportControls?.skipToPrevious()
                result.success(true)
            }
            "getPlaybackState" -> {
                refreshActiveController()
                val isPlaying = activeController?.playbackState?.state == PlaybackState.STATE_PLAYING
                result.success(isPlaying)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
        startListening()
        sendMediaStateUpdate()
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
        stopListening()
    }
}
