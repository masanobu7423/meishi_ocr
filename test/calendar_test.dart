// カレンダーに登録: the platform's "new event" screen, pre-filled, via one
// method channel (no calendar permission, the user confirms in their app).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/calendar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(calendarChannel, null));

  test('addToCalendar sends title, date and description and reports the platform result', () async {
    MethodCall? seen;
    messenger.setMockMethodCallHandler(calendarChannel, (call) async {
      seen = call;
      return true;
    });
    final ok = await addToCalendar(title: '連絡: 山田 太郎', date: '2026-11-03', description: '電話 03-1234-5678');
    expect(ok, isTrue);
    expect(seen!.method, 'insertEvent');
    expect(seen!.arguments, {'title': '連絡: 山田 太郎', 'date': '2026-11-03', 'description': '電話 03-1234-5678'});
  });

  test('addToCalendar is false when no calendar app answers or the date is not a date', () async {
    messenger.setMockMethodCallHandler(calendarChannel, (call) async => throw PlatformException(code: 'no_app'));
    expect(await addToCalendar(title: 't', date: '2026-11-03', description: ''), isFalse);
    expect(await addToCalendar(title: 't', date: 'tomorrow', description: ''), isFalse);
  });
}
