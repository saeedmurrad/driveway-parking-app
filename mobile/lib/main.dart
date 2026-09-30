import 'package:flutter/material.dart';
import 'src/api.dart';

void main() => runApp(const ParkSpaceApp());

class ParkSpaceApp extends StatelessWidget {
  const ParkSpaceApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ParkSpace',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const SearchScreen(),
      );
}

/// POC driver home: searches near Kings Cross for the next 2 hours.
/// TODO: swap the list for a map (MapLibre) with price pins, add booking + Stripe.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _api = Api();
  late Future<List<Listing>> _results = _load();

  Future<List<Listing>> _load() {
    final start = DateTime.now().add(const Duration(minutes: 30));
    return _api.search(
      lat: 51.5308,
      lng: -0.1238,
      start: start,
      end: start.add(const Duration(hours: 2)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ParkSpace — find a driveway')),
        body: FutureBuilder<List<Listing>>(
          future: _results,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Could not load spaces.\n${snap.error}'));
            }
            final items = snap.data!;
            if (items.isEmpty) return const Center(child: Text('No spaces free nearby.'));
            return ListView(
              children: [
                for (final l in items)
                  ListTile(
                    leading: const Icon(Icons.local_parking),
                    title: Text(l.title),
                    subtitle: Text('${((l.distanceM ?? 0) / 1000).toStringAsFixed(1)} km away'),
                    trailing: Text('£${l.priceHour.toStringAsFixed(2)}/h'),
                  ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => setState(() => _results = _load()),
          child: const Icon(Icons.refresh),
        ),
      );
}
