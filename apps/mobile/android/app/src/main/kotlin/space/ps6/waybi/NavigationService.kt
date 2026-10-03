package space.ps6.waybi

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/** Active trips keep location delivery alive with a visible system surface. */
class NavigationService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "Waybi navigation", NotificationManager.IMPORTANCE_LOW)
        )
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Waybi:Navigation")
            .also { it.acquire(8 * 60 * 60 * 1000L) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val destination = intent?.getStringExtra("destination") ?: "Waybi"
        val instruction = intent?.getStringExtra("instruction") ?: "Navigation active"
        val distance = intent?.getStringExtra("distance") ?: ""
        val remaining = intent?.getStringExtra("remaining") ?: ""
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_navigation)
            .setColor(0xFFA8D86A.toInt())
            .setContentTitle("$distance · $instruction")
            .setContentText("$destination · $remaining")
            .setStyle(Notification.BigTextStyle().bigText("$instruction\n$destination · $remaining"))
            .setContentIntent(open)
            .setCategory(Notification.CATEGORY_NAVIGATION)
            .setOngoing(true).setOnlyAlertOnce(true).setShowWhen(false)
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(ID, notification)
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) { stopSelf() }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val CHANNEL = "waybi_navigation_live"
        const val ID = 4207
    }
}
