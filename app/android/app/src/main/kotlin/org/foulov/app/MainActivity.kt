package org.foulov.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Canal « Messages » : la notification arrive avec le son et la vibration par défaut du téléphone.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("messages", "Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Nouveaux messages de ton amour (jamais leur contenu)"
                // Rien sur l'écran verrouillé au-delà du texte fixe.
                lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "foulove/notifications").setMethodCallHandler { call, result ->
            when (call.method) {
                // La conversation est ouverte : les notifications déjà affichées n'ont plus lieu d'être.
                "clear" -> {
                    getSystemService(NotificationManager::class.java).cancelAll()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
