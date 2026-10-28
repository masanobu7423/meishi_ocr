import 'package:flutter/services.dart';

import 'ocr/history.dart';

/// The one method channel to MainActivity: opens the platform's "new
/// event" screen pre-filled (all-day on [date]); the user confirms there,
/// so the app needs no calendar permission and the calendar app does the
/// reminding.
const calendarChannel = MethodChannel('jp.tobishoku.meishi_ocr/calendar');

/// False when [date] is not yyyy-mm-dd or no calendar app could be opened.
Future<bool> addToCalendar({required String title, required String date, required String description}) async {
  if (parseYmd(date) == null) return false;
  try {
    return await calendarChannel.invokeMethod<bool>(
            'insertEvent', {'title': title, 'date': date, 'description': description}) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
