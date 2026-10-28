import 'dart:convert';

import 'history.dart';

/// 連絡予定 as iCalendar (RFC 5545): one all-day VEVENT per card with a
/// valid 次回連絡日, so Google / Outlook / the phone's calendar can import
/// every follow-up at once and remind the user their own way.
String icsOfCards(List<CardSummary> cards, {DateTime? now}) {
  final stamp = _utcStamp((now ?? DateTime.now()).toUtc());
  final b = StringBuffer()
    ..write('BEGIN:VCALENDAR\r\n')
    ..write('VERSION:2.0\r\n')
    ..write('PRODID:-//meishi_ocr//名刺スキャン//JA\r\n');
  for (final c in byNextContact(cards)) {
    final d = parseYmd(c.nextContact)!;
    final next = DateTime(d.year, d.month, d.day + 1);
    for (final line in [
      'BEGIN:VEVENT',
      'UID:${c.stem}@meishi_ocr',
      'DTSTAMP:$stamp',
      'DTSTART;VALUE=DATE:${_date(d)}',
      'DTEND;VALUE=DATE:${_date(next)}',
      'SUMMARY:${_esc(eventTitle(c.name, c.company))}',
      'DESCRIPTION:${_esc(eventDescription(phone: c.phone, mobile: c.mobile, email: c.email))}',
      'END:VEVENT',
    ]) {
      b.write('${_fold(line)}\r\n');
    }
  }
  b.write('END:VCALENDAR\r\n');
  return b.toString();
}

/// "連絡: 氏名（会社）": the event title, shared with the calendar intent.
String eventTitle(String name, String? company) =>
    '連絡: $name${company == null || company.isEmpty ? '' : '（$company）'}';

/// Phone / mobile / e-mail lines and the app name, newline-separated.
String eventDescription({String? phone, String? mobile, String? email}) => [
      if (phone != null && phone.isNotEmpty) '電話 $phone',
      if (mobile != null && mobile.isNotEmpty) '携帯 $mobile',
      if (email != null && email.isNotEmpty) 'メール $email',
      '名刺スキャン',
    ].join('\n');

String _date(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

String _utcStamp(DateTime u) => '${_date(u)}T${u.hour.toString().padLeft(2, '0')}'
    '${u.minute.toString().padLeft(2, '0')}${u.second.toString().padLeft(2, '0')}Z';

/// Text escaping: backslash, comma, semicolon, newline.
String _esc(String s) =>
    s.replaceAll('\\', '\\\\').replaceAll(',', '\\,').replaceAll(';', '\\;').replaceAll('\n', '\\n');

/// RFC 5545 §3.1: lines longer than 75 octets are folded with CRLF + one
/// space (which counts as the first octet of the next line). Counted in
/// UTF-8 octets, never splitting a character (Japanese is 3 octets each).
String _fold(String line) {
  final out = StringBuffer();
  var octets = 0;
  for (final r in line.runes) {
    final ch = String.fromCharCode(r);
    final n = utf8.encode(ch).length;
    if (octets + n > 75) {
      out.write('\r\n ');
      octets = 1;
    }
    out.write(ch);
    octets += n;
  }
  return out.toString();
}
