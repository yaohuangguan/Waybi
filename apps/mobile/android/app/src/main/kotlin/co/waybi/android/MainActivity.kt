package co.waybi.android

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.LocaleList
import android.provider.Settings
import java.util.Locale

class MainActivity : FlutterActivity() {
    override fun attachBaseContext(base: Context) {
        val language = base.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.waybi.app.language", null)
            ?: base.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.kiwi.app.language", null)
        if (language == null) { super.attachBaseContext(base); return }
        val locale = Locale.forLanguageTag(if (language == "zh") "zh-CN" else "en-NZ")
        val config = Configuration(base.resources.configuration)
        config.setLocale(locale)
        super.attachBaseContext(base.createConfigurationContext(config))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "waybi/system_navigation")
            .setMethodCallHandler { call, result ->
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                val intent = Intent(this, NavigationService::class.java)
                when (call.method) {
                    "start", "update" -> {
                        // Google's own navigator already owns its system notification.
                        if (args["provider"] == "google") { result.success(true); return@setMethodCallHandler }
                        for (key in listOf("destination", "instruction", "distance", "remaining")) {
                            intent.putExtra(key, args[key] as? String ?: "")
                        }
                        try {
                            if (call.method == "start") startForegroundService(intent)
                            else startService(intent)
                            result.success(true)
                        } catch (error: RuntimeException) {
                            result.error("NAVIGATION_SERVICE_UNAVAILABLE", error.javaClass.simpleName, null)
                        }
                    }
                    "stop" -> { stopService(intent); result.success(true) }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "waybi/map_language")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setLanguage" -> {
                        val locale = Locale.forLanguageTag(if (call.arguments == "zh") "zh-CN" else "en-NZ")
                        val previousLanguage = resources.configuration.locales[0].language
                        Locale.setDefault(locale)
                        for (target in listOf(resources, applicationContext.resources)) {
                            val config = Configuration(target.configuration)
                            config.setLocales(LocaleList(locale))
                            @Suppress("DEPRECATION")
                            target.updateConfiguration(config, target.displayMetrics)
                        }
                        // SDK renderers may cache their language. A changed
                        // locale requires reopening the app for native labels.
                        result.success(previousLanguage == locale.language)
                    }
                    "openSettings" -> {
                        val action = if (Build.VERSION.SDK_INT >= 33) Settings.ACTION_APP_LOCALE_SETTINGS
                            else Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                        startActivity(Intent(action, Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
