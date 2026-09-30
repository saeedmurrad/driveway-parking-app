import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Triggers a browser file download. Returns true if a real file download happened.
Future<bool> downloadText(String filename, String content, {String mime = 'text/csv'}) async {
  final blob = web.Blob([content.toJS].toJS, web.BlobPropertyBag(type: '$mime;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  a.click();
  web.URL.revokeObjectURL(url);
  return true;
}
