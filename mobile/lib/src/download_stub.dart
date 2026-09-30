import 'package:flutter/services.dart';

/// Non-web fallback: copies the text to the clipboard. Returns true if a real file download happened.
Future<bool> downloadText(String filename, String content, {String mime = 'text/csv'}) async {
  await Clipboard.setData(ClipboardData(text: content));
  return false;
}
