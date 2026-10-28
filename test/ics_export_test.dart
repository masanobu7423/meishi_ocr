// 連絡予定 as an iCalendar file: one all-day event per dated card, so any
// calendar (Google, Outlook, the phone's) can import the follow-ups.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/history.dart';
import 'package:meishi_ocr/ocr/ics_export.dart';

void main() {
  final now = DateTime.utc(2026, 10, 28, 0, 30);
  const cards = [
    CardSummary(noteStem: 'a', stem: 'k01', name: '山田 太郎', company: '株式会社サンライズ', phone: '03-1234-5678',
        email: 'taro@example.com', nextContact: '2026-11-03'),
    CardSummary(noteStem: 'b', stem: 'k02', name: '鈴木, 一郎; 2', nextContact: '2026-12-31'),
    CardSummary(noteStem: 'c', stem: 'k03', name: '佐藤 花子'),
    CardSummary(noteStem: 'd', stem: 'k04', name: '田中', nextContact: '2026-13-45'),
  ];

  test('icsOfCards: a VCALENDAR with one all-day VEVENT per valid date, CRLF, escaped text', () {
    final ics = icsOfCards(cards, now: now);
    final flat = ics.replaceAll('\r\n ', ''); // unfolded
    expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect('BEGIN:VEVENT'.allMatches(ics).length, 2, reason: 'undated and invalid dates are skipped');
    expect(flat, contains('DTSTART;VALUE=DATE:20261103\r\nDTEND;VALUE=DATE:20261104\r\n'));
    expect(flat, contains('SUMMARY:連絡: 山田 太郎（株式会社サンライズ）\r\n'));
    expect(flat, contains('DESCRIPTION:電話 03-1234-5678\\nメール taro@example.com\\n名刺スキャン\r\n'));
    expect(flat, contains('UID:k01@meishi_ocr\r\n'));
    expect(flat, contains('DTSTAMP:20261028T003000Z\r\n'), reason: 'now in UTC');
    expect(flat, contains('SUMMARY:連絡: 鈴木\\, 一郎\\; 2\r\n'), reason: 'commas and semicolons escaped');
    expect(flat, contains('DTSTART;VALUE=DATE:20261231\r\nDTEND;VALUE=DATE:20270101\r\n'));
    expect(ics.split('\r\n').every((l) => utf8.encode(l).length <= 75), isTrue, reason: '75 octets or shorter');
  });

  test('long Japanese lines are folded by octets and unfold back to the original', () {
    const long = CardSummary(
        noteStem: 'x', stem: 'k99', name: '国土交通省関東地方整備局 建設太郎',
        company: '株式会社サンライズ建設工業東京支店営業第二部', nextContact: '2026-11-03');
    final ics = icsOfCards([long], now: now);
    final lines = ics.split('\r\n');
    expect(lines.every((l) => utf8.encode(l).length <= 75), isTrue);
    expect(lines.where((l) => l.startsWith(' ')).isNotEmpty, isTrue, reason: 'something was folded');
    final unfolded = ics.replaceAll('\r\n ', '');
    expect(unfolded, contains('SUMMARY:${eventTitle(long.name, long.company)}\r\n'));
  });

  test('icsOfCards with nothing dated is an empty calendar', () {
    final ics = icsOfCards([cards[2]], now: now);
    expect(ics, isNot(contains('VEVENT')));
  });
}
