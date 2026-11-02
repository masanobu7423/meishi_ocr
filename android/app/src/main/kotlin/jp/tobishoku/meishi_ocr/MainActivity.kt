package jp.tobishoku.meishi_ocr

import android.app.Activity
import android.content.Intent
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Calendar
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private var pendingZip: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "pickZip": the system document picker (Drive, Downloads, …) for a backup
        // zip. The picked file is copied into the cache and its path returned;
        // null when cancelled. No storage permission: the user picks the file.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jp.tobishoku.meishi_ocr/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickZip") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                pendingZip?.success(null) // a second tap replaces a forgotten picker
                pendingZip = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("*/*")
                    // Drive and some file apps label a zip as octet-stream.
                    .putExtra(
                        Intent.EXTRA_MIME_TYPES,
                        arrayOf("application/zip", "application/x-zip-compressed", "application/octet-stream"),
                    )
                try {
                    startActivityForResult(intent, PICK_ZIP)
                } catch (e: Exception) {
                    pendingZip = null
                    result.error("no_picker", e.message, null)
                }
            }
        // "insertEvent": the calendar app's new-event screen, pre-filled with an
        // all-day event on the given yyyy-mm-dd. No permission: the user saves it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jp.tobishoku.meishi_ocr/calendar")
            .setMethodCallHandler { call, result ->
                if (call.method != "insertEvent") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val ymd = call.argument<String>("date")!!.split("-").map { it.toInt() }
                    // All-day events are expressed as UTC midnight (CalendarContract). The
                    // app targets Japan (UTC+9): a negative-offset zone would show the day before.
                    val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                        clear()
                        set(ymd[0], ymd[1] - 1, ymd[2])
                    }
                    val begin = cal.timeInMillis
                    val intent = Intent(Intent.ACTION_INSERT)
                        .setData(CalendarContract.Events.CONTENT_URI)
                        .putExtra(CalendarContract.Events.TITLE, call.argument<String>("title"))
                        .putExtra(CalendarContract.Events.DESCRIPTION, call.argument<String>("description"))
                        .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, begin)
                        .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, begin + 86_400_000L)
                        .putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, true)
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("no_app", e.message, null)
                }
            }
    }

    // FlutterActivity is a plain Activity: this is its result hook.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_ZIP) return
        val result = pendingZip ?: return
        pendingZip = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // Off the main thread: a backup with photos can be tens of MB.
        Thread {
            try {
                val out = File(cacheDir, "restore_pick.zip")
                var copied = 0L
                contentResolver.openInputStream(uri)!!.use { input ->
                    out.outputStream().use { output ->
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            copied += n
                            // A backup is tens of MB; a huge pick is the wrong file.
                            if (copied > MAX_ZIP) throw IllegalStateException("too_large")
                            output.write(buf, 0, n)
                        }
                    }
                }
                runOnUiThread { result.success(out.path) }
            } catch (e: Exception) {
                File(cacheDir, "restore_pick.zip").delete()
                val code = if (e.message == "too_large") "too_large" else "copy"
                runOnUiThread { result.error(code, e.message, null) }
            }
        }.start()
    }

    private companion object {
        const val PICK_ZIP = 4201
        const val MAX_ZIP = 512L * 1024 * 1024
    }
}
