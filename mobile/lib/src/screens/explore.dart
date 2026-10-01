import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'space_detail.dart';

const _places = {
  "King's Cross": LatLng(51.5308, -0.1238),
  'Camden': LatLng(51.5390, -0.1426),
  'Shoreditch': LatLng(51.5254, -0.0786),
  'Waterloo': LatLng(51.5031, -0.1132),
  'Canary Wharf': LatLng(51.5054, -0.0235),
};

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _map = MapController();
  final _query = TextEditingController();
  LatLng _center = _places["King's Cross"]!;
  bool _startNow = true;
  DateTime _start = DateTime.now();
  int _hours = 2;
  final Set<String> _filters = {};
  bool _instantOnly = false;
  double? _maxPrice;
  String _sort = 'distance';
  List<Json> _all = [];
  bool _loading = true;
  String? _error, _selected;

  DateTime get _from => _startNow ? DateTime.now().add(const Duration(minutes: 2)) : _start;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _search() async {
    final s = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    final from = _from;
    try {
      final res = await s.api.get('/listings/search', query: {
        'lat': '${_center.latitude}',
        'lng': '${_center.longitude}',
        'start': from.toUtc().toIso8601String(),
        'end': from.add(Duration(hours: _hours)).toUtc().toIso8601String(),
        'vehicleSize': '${s.vehicle?['size'] ?? 'medium'}',
        'radius': '4000',
      }) as List;
      if (!mounted) return;
      setState(() {
        _all = res.map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
        _selected = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<Json> get _results {
    final r = _all
        .where((l) => _filters.every((f) => (l['features'] as List).contains(f)))
        .where((l) => !_instantOnly || l['booking_mode'] == 'instant')
        .where((l) => _maxPrice == null || num_(l['price_hour']) <= _maxPrice!)
        .toList();
    r.sort((a, b) => switch (_sort) {
          'price' => num_(a['quote']['total']).compareTo(num_(b['quote']['total'])),
          'rating' => num_(b['rating']).compareTo(num_(a['rating'])),
          _ => num_(a['distance_m']).compareTo(num_(b['distance_m'])),
        });
    return r;
  }

  void _moveTo(LatLng p) {
    _center = p;
    _map.move(p, 14);
    _search();
  }

  Future<void> _geocode(String q) async {
    if (q.trim().isEmpty) return;
    try {
      final res = await http.get(Uri.parse('https://nominatim.openstreetmap.org/search').replace(
          queryParameters: {'format': 'json', 'limit': '1', 'countrycodes': 'gb', 'q': q}));
      final list = jsonDecode(res.body) as List;
      if (list.isEmpty) {
        if (mounted) toast(context, 'Could not find "$q"', error: true);
        return;
      }
      _moveTo(LatLng(double.parse(list[0]['lat']), double.parse(list[0]['lon'])));
    } catch (_) {
      if (mounted) toast(context, 'Place search is unavailable right now', error: true);
    }
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 60)), initialDate: _start.isBefore(now) ? now : _start);
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t == null) return;
    setState(() {
      _startNow = false;
      _start = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
    _search();
  }

  void _open(Json l) => Navigator.push(context, MaterialPageRoute(
      builder: (_) => SpaceDetail(listingId: l['id'], start: _from, end: _from.add(Duration(hours: _hours)))));

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final results = _results;
    final list = _ResultList(results: results, loading: _loading, error: _error, selected: _selected, hours: _hours, onTap: _open, onRetry: _search);
    final map = _MapPane(
      controller: _map, center: _center, results: results, selected: _selected,
      onSelect: (id) => setState(() => _selected = id), onOpen: _open,
    );
    return Column(children: [
      _controls(context),
      Expanded(
        child: wide
            ? Row(children: [SizedBox(width: 460, child: list), Expanded(child: map)])
            : Column(children: [Expanded(flex: 5, child: map), Expanded(flex: 5, child: list)]),
      ),
    ]);
  }

  Widget _controls(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Color(0x141B2559), blurRadius: 16, offset: Offset(0, 6))],
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _geocode,
                  decoration: InputDecoration(
                    hintText: 'Where are you going? (address or postcode)',
                    prefixIcon: const Icon(Icons.search),
                    contentPadding: EdgeInsets.zero,
                    suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _geocode(_query.text)),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              ActionChip(
                avatar: const Icon(Icons.schedule, size: 16),
                label: Text(_startNow ? 'Starts now' : '${fmtDay(_start)} ${fmtTime(_start)}'),
                onPressed: _pickStart,
              ),
              if (!_startNow) Padding(padding: const EdgeInsets.only(left: 4), child: IconButton(
                visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 16),
                onPressed: () { setState(() => _startNow = true); _search(); })),
              const SizedBox(width: 8),
              for (final h in [1, 2, 4, 8, 24])
                Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
                  label: Text(h == 24 ? '1 day' : '${h}h'), selected: _hours == h,
                  onSelected: (_) { setState(() => _hours = h); _search(); })),
              const SizedBox(width: 6),
              const SizedBox(height: 24, child: VerticalDivider()),
              const SizedBox(width: 6),
              Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(
                avatar: const Icon(Icons.bolt, size: 16), label: const Text('Instant book'), selected: _instantOnly,
                onSelected: (v) => setState(() => _instantOnly = v))),
              Padding(padding: const EdgeInsets.only(right: 6), child: PopupMenuButton<double?>(
                onSelected: (v) => setState(() => _maxPrice = v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: null, child: Text('Any price')),
                  PopupMenuItem(value: 2.5, child: Text('Up to £2.50/h')),
                  PopupMenuItem(value: 3.0, child: Text('Up to £3.00/h')),
                  PopupMenuItem(value: 4.0, child: Text('Up to £4.00/h')),
                ],
                child: Chip(
                  avatar: const Icon(Icons.sell_outlined, size: 16),
                  label: Text(_maxPrice == null ? 'Price' : '≤ £${_maxPrice!.toStringAsFixed(2)}/h'),
                  backgroundColor: _maxPrice == null ? null : const Color(0xFFDDE7FF),
                ),
              )),
              for (final f in const ['covered', 'cctv', 'ev_charging', 'gated'])
                Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(
                  avatar: Icon(featureIcons[f]!.$1, size: 16), label: Text(featureIcons[f]!.$2), selected: _filters.contains(f),
                  onSelected: (v) => setState(() => v ? _filters.add(f) : _filters.remove(f)))),
            ]),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: ClipRect(child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final e in _places.entries)
                    Padding(padding: const EdgeInsets.only(right: 6), child: ActionChip(
                      label: Text(e.key), visualDensity: VisualDensity.compact, onPressed: () => _moveTo(e.value))),
                ]),
              )),
            ),
            DropdownButton<String>(
              value: _sort, underline: const SizedBox(), isDense: true,
              items: const [
                DropdownMenuItem(value: 'distance', child: Text('Nearest')),
                DropdownMenuItem(value: 'price', child: Text('Cheapest')),
                DropdownMenuItem(value: 'rating', child: Text('Top rated')),
              ],
              onChanged: (v) => setState(() => _sort = v!),
            ),
          ]),
        ]),
      );
}

class _MapPane extends StatelessWidget {
  const _MapPane({required this.controller, required this.center, required this.results, required this.selected, required this.onSelect, required this.onOpen});
  final MapController controller;
  final LatLng center;
  final List<Json> results;
  final String? selected;
  final void Function(String?) onSelect;
  final void Function(Json) onOpen;

  @override
  Widget build(BuildContext context) {
    final sel = results.where((l) => l['id'] == selected).firstOrNull;
    return Stack(children: [
      FlutterMap(
        mapController: controller,
        options: MapOptions(initialCenter: center, initialZoom: 14, onTap: (_, _) => onSelect(null)),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.parkspace.app'),
          MarkerLayer(markers: [
            Marker(point: center, width: 18, height: 18, child: Container(
              decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)]))),
            for (final l in results)
              Marker(
                point: LatLng(num_(l['latitude']), num_(l['longitude'])),
                width: 78, height: 38, alignment: Alignment.topCenter,
                child: GestureDetector(onTap: () => onSelect(l['id']), child: _PricePin(text: money(l['price_hour']), selected: l['id'] == selected)),
              ),
          ]),
          const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
        ],
      ),
      if (sel != null)
        Positioned(
          left: 12, right: 12, bottom: 12,
          child: Card(child: ListTile(
            leading: Icon(spaceIcons[sel['space_type']] ?? Icons.local_parking, color: brand),
            title: Text(sel['title'], maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${money(sel['quote']['total'])} total · ${(num_(sel['distance_m']) / 1000).toStringAsFixed(1)} km'),
            trailing: FilledButton(onPressed: () => onOpen(sel), child: const Text('View')),
          )),
        ),
    ]);
  }
}

class _PricePin extends StatelessWidget {
  const _PricePin({required this.text, required this.selected});
  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF14171F) : brand, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(blurRadius: 10, color: Color(0x40000000), offset: Offset(0, 3))],
          ),
          child: Text('$text/h', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ),
      ]);
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.results, required this.loading, required this.error, required this.selected, required this.hours, required this.onTap, required this.onRetry});
  final List<Json> results;
  final bool loading;
  final String? error, selected;
  final int hours;
  final void Function(Json) onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error!), const SizedBox(height: 8), FilledButton.tonal(onPressed: onRetry, child: const Text('Try again'))]));
    }
    if (results.isEmpty) return const EmptyState(Icons.search_off, 'No spaces free here', subtitle: 'Try another area, a shorter stay or fewer filters.');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: results.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) return Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('${results.length} space${results.length == 1 ? '' : 's'} available', style: const TextStyle(fontWeight: FontWeight.w600)));
        final l = results[i - 1];
        final feats = (l['features'] as List).cast<String>();
        final isSel = l['id'] == selected;
        return Card(
          elevation: isSel ? 6 : 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: isSel ? brand : Colors.transparent, width: 2)),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => onTap(l),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 96, height: 96,
                    child: l['photo_url'] != null
                        ? Image.network(mediaUrl(l['photo_url']), fit: BoxFit.cover, errorBuilder: (_, _, _) => _thumbFallback(l))
                        : _thumbFallback(l),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Stars(l['rating']),
                    Flexible(child: Text('   ${(num_(l['distance_m']) / 80).ceil()} min walk · ${l['host_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54))),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final f in feats.take(3))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFF0F3FB), borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(featureIcons[f]?.$1 ?? Icons.check, size: 12, color: Colors.black54), const SizedBox(width: 4),
                          Text(featureIcons[f]?.$2 ?? f, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ]),
                      ),
                    if (l['booking_mode'] == 'request') _tag('Request', Colors.orange),
                    if (l['allow_offers'] == true) _tag('Offers', Colors.teal),
                  ]),
                ])),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(money(l['quote']['total']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: brand)),
                  Text('for ${hours == 24 ? '1 day' : '${hours}h'}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Text('${money(l['price_hour'])}/h', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }
}

Widget _thumbFallback(Json l) => Container(
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFDDE7FF), Color(0xFFB9CDFF)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Icon(spaceIcons[l['space_type']] ?? Icons.local_parking, color: brand, size: 30),
    );

Widget _tag(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
    );
