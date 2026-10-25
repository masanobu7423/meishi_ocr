import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/card_status.dart';

void main() {
  test('labels are Japanese and parse back; legacy notes count as reviewed', () {
    expect(CardStatus.unreviewed.label, '未確認');
    expect(CardStatus.reviewed.label, '確認済');
    expect(CardStatus.registered.label, '登録済');
    for (final s in CardStatus.values) {
      expect(parseStatus(s.label), s);
      expect(parseStatus(s.name), s, reason: 'JSON uses the enum name');
    }
    expect(parseStatus(null), CardStatus.reviewed);
    expect(parseStatus('?'), CardStatus.reviewed);
  });
}
