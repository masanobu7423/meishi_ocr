import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/card_note.dart';

void main() {
  test('safeFileStem strips path and OS-illegal characters, names the nameless', () {
    expect(safeFileStem('山田/太郎 :*?"<>|'), '山田_太郎________');
    expect(safeFileStem(r'..\up'), '.._up');
    expect(safeFileStem(''), '名無し');
    expect(safeFileStem(null), '名無し');
  });
}
