import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/app_shell.dart';

void main() {
  test('backupLabel shows the backup time, or the raw name', () {
    expect(backupLabel(File('/x/backup/meishi_backup_2026-10-25_1745.zip')), '2026-10-25 17:45');
    expect(backupLabel(File('/x/backup/from_other_phone.zip')), 'from_other_phone.zip');
  });
}
