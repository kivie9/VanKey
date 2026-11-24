package com.vankey.vankey

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Cầu nối nhỏ tới Android cho hai việc Flutter không tự làm được:
 * - FLAG_SECURE: chặn chụp màn hình và che nội dung trong danh sách ứng dụng gần đây.
 * - Chép vào clipboard kèm cờ "nhạy cảm" để Android 13+ không hiện bản xem trước nội dung.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vankey/platform").setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val on = call.argument<Boolean>("on") ?: true
                    if (on) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                "copySensitive" -> {
                    val text = call.argument<String>("text") ?: ""
                    val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = ClipData.newPlainText("VanKey", text)
                    val extras = PersistableBundle()
                    // Android 13+ dùng khóa chuẩn; bản cũ hơn dùng khóa riêng của Samsung/AOSP trước đó.
                    val key = if (Build.VERSION.SDK_INT >= 33) ClipDescription.EXTRA_IS_SENSITIVE else "android.content.extra.IS_SENSITIVE"
                    extras.putBoolean(key, true)
                    clip.description.extras = extras
                    cm.setPrimaryClip(clip)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
