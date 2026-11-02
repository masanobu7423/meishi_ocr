import 'dart:io';

import 'package:flutter/services.dart';

/// MainActivity's file channel: the system document picker, so a backup zip
/// in Drive or Downloads can be restored (Android 11+ hides the app folder
/// from the Files app). No new dependency, no storage permission.
const filesChannel = MethodChannel('jp.tobishoku.meishi_ocr/files');

/// The picked zip, copied into the app's cache; null when cancelled (or no
/// picker on this platform). A failed copy throws [PlatformException]
/// (`too_large`, `copy`, `no_picker`) so the caller can say what happened.
Future<File?> pickBackupZip() async {
  try {
    final path = await filesChannel.invokeMethod<String>('pickZip');
    return path == null ? null : File(path);
  } on MissingPluginException {
    return null;
  }
}
