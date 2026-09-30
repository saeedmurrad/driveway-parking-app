import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Backend base URL. Override at build time:
/// flutter build web --dart-define=API_URL=https://parkspace-api.onrender.com
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

class ApiException implements Exception {
  ApiException(this.message, this.status);
  final String message;
  final int status;
  @override
  String toString() => message;
}

typedef Json = Map<String, dynamic>;

/// Uploaded files are served by the API (e.g. /uploads/abc.png); full URLs pass through.
String mediaUrl(String path) => path.startsWith('http') ? path : '$apiUrl$path';

MediaType _mediaType(String m) => MediaType.parse(m);

class Api {
  String? token;

  Future<dynamic> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    final uri = Uri.parse('$apiUrl$path').replace(queryParameters: query);
    final headers = {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
    http.Response res;
    try {
      res = switch (method) {
        'POST' => await http.post(uri, headers: headers, body: jsonEncode(body ?? {})),
        'PUT' => await http.put(uri, headers: headers, body: jsonEncode(body ?? {})),
        'PATCH' => await http.patch(uri, headers: headers, body: jsonEncode(body ?? {})),
        'DELETE' => await http.delete(uri, headers: headers),
        _ => await http.get(uri, headers: headers),
      };
    } catch (_) {
      throw ApiException('Cannot reach the server. Is the API running?', 0);
    }
    final data = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final m = data is Map ? data['message'] : null;
      throw ApiException(m is List ? m.join('\n') : (m?.toString() ?? 'Something went wrong'), res.statusCode);
    }
    return data;
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);

  /// Raw text response (CSV statements).
  Future<String> getText(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$apiUrl$path').replace(queryParameters: query);
    try {
      final res = await http.get(uri, headers: {if (token != null) 'authorization': 'Bearer $token'});
      if (res.statusCode >= 400) {
        final d = jsonDecode(res.body);
        throw ApiException('${d['message'] ?? 'Something went wrong'}', res.statusCode);
      }
      return utf8.decode(res.bodyBytes);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Cannot reach the server. Is the API running?', 0);
    }
  }

  /// Uploads an image and returns its URL path.
  Future<String> upload(Uint8List bytes, String filename, String mime) async {
    final req = http.MultipartRequest('POST', Uri.parse('$apiUrl/uploads'))
      ..headers['authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: _mediaType(mime)));
    try {
      final res = await http.Response.fromStream(await req.send());
      final data = jsonDecode(res.body);
      if (res.statusCode >= 400) throw ApiException('${data['message'] ?? 'Upload failed'}', res.statusCode);
      return data['url'];
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Upload failed. Is the API running?', 0);
    }
  }
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);
  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);
}
