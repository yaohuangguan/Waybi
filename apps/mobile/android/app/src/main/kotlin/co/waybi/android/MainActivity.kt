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
import android.app.Dialog
import android.graphics.Color
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceError
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.LinearLayout
import android.widget.Button
import org.json.JSONObject

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "waybi/google_place_picker")
            .setMethodCallHandler { call, result ->
                val args = call.arguments as? Map<*, *>
                val uri = (args?.get("url") as? String)?.let(Uri::parse)
                if (call.method != "open" || uri?.scheme != "https" || uri.host != "waybi.co" || uri.path != "/api/search/google" || uri.userInfo != null || uri.port != -1) {
                    result.error("invalid_picker", "Invalid search page", null)
                    return@setMethodCallHandler
                }
                val dialog = Dialog(this, android.R.style.Theme_Material_Light_NoActionBar)
                val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.WHITE) }
                val web = WebView(this)
                val nonce = java.util.UUID.randomUUID().toString()
                var finished = false
                fun finish(value: String?) {
                    if (finished) return
                    finished = true
                    web.stopLoading(); web.removeJavascriptInterface("WaybiPlaces"); dialog.dismiss(); web.destroy(); result.success(value)
                }
                val close = Button(this).apply { text = "← Waybi"; setOnClickListener { finish(null) } }
                column.addView(close)
                column.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
                web.settings.javaScriptEnabled = true
                web.settings.domStorageEnabled = true
                web.settings.allowFileAccess = false
                web.settings.allowContentAccess = false
                web.addJavascriptInterface(object {
                    @JavascriptInterface fun postMessage(body: String) {
                        runOnUiThread {
                            val validNonce = try { JSONObject(body).optString("nonce") == nonce } catch (_: Exception) { false }
                            if (body.length < 4096 && validNonce && web.url?.startsWith("https://waybi.co/api/search/google") == true) finish(body)
                        }
                    }
                }, "WaybiPlaces")
                web.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                        if (!request.isForMainFrame) return false
                        val next = request.url
                        return !(next.scheme == "https" && next.host == "waybi.co" && next.path == "/api/search/google")
                    }
                    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                        if (request.isForMainFrame) finish(JSONObject().put("status", "fallback").put("query", uri.getQueryParameter("q") ?: "").toString())
                    }
                }
                dialog.setContentView(column)
                dialog.setOnCancelListener { finish(null) }
                dialog.show()
                dialog.window?.setLayout(-1, -1)
                web.loadUrl(uri.buildUpon().fragment(nonce).build().toString())
            }
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
