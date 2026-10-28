package jp.tobishoku.meishi_ocr

import android.content.Intent
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
