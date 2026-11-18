package org.foulov.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity : requise par la boîte de dialogue biométrique (local_auth).
class MainActivity : FlutterFragmentActivity() {
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
                // Verrouillage actif : la vignette des apps récentes ne montre pas la conversation (Android 13+).
                // Les captures d'écran restent possibles, contrairement à FLAG_SECURE.
                "hideInRecents" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        setRecentsScreenshotEnabled(call.arguments != true)
                    }
                    result.success(null)
                }
                // Écran sensible (phrase de récupération) : ni capture d'écran, ni aperçu dans les apps récentes.
                "secure" -> {
                    if (call.arguments == true) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
