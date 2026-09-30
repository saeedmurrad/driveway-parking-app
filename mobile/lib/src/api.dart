import 'dart:convert';
import 'package:http/http.dart' as http;

/// Backend base URL. Override at build time:
/// flutter build web --dart-define=API_URL=https://parkspace-api.onrender.com
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

class Listing {
  Listing.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        title = j['title'],
        lat = (j['latitude'] as num).toDouble(),
        lng = (j['longitude'] as num).toDouble(),
        priceHour = double.parse('${j['price_hour']}'),
        distanceM = (j['distance_m'] as num?)?.toDouble();

  final String id, title;
  final double lat, lng, priceHour;
  final double? distanceM;
}

class Api {
  Future<List<Listing>> search({
    required double lat,
    required double lng,
    required DateTime start,
    required DateTime end,
  }) async {
    final uri = Uri.parse('$apiUrl/listings/search').replace(queryParameters: {
      'lat': '$lat',
      'lng': '$lng',
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('Search failed (${res.statusCode})');
    return (jsonDecode(res.body) as List).map((e) => Listing.fromJson(e)).toList();
  }
}
