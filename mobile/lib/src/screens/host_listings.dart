import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'availability.dart';

class HostListings extends StatelessWidget {
  const HostListings({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<Json>>(
      load: () async => ((await api.get('/me/listings')) as List).map((e) => Map<String, dynamic>.from(e)).toList(),
      builder: (context, items, reload) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddListing()));
            if (added == true) reload();
          },
          icon: const Icon(Icons.add), label: const Text('Add a space'),
        ),
        body: RefreshIndicator(
          onRefresh: reload,
          child: items.isEmpty
              ? ListView(children: const [SizedBox(height: 400, child: EmptyState(Icons.home_work_outlined, 'No spaces yet', subtitle: 'Add your driveway and start earning.'))])
              : ListView(padding: const EdgeInsets.only(bottom: 90), children: [
                  Centered(child: Column(children: [
                    for (final l in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ListingCard(l: l, onChanged: reload)),
                  ])),
                ]),
        ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.l, required this.onChanged});
  final Json l;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final status = l['status'] as String;
    final toggleable = status == 'live' || status == 'paused';
    final api = context.read<AppState>().api;
    return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(color: const Color(0xFFDDE7FF), borderRadius: BorderRadius.circular(12)),
          child: Icon(spaceIcons[l['space_type']] ?? Icons.local_parking, color: brand),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l['title'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          Text(l['address'], style: const TextStyle(color: Colors.black54, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        StatusChip(status),
      ]),
      const Divider(height: 24),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _stat('Price', '${money(l['price_hour'])}/h'),
        _stat('Bookings', '${l['bookings_count']}'),
        _stat('Earned', money(l['earnings'])),
        Column(children: [const Text('Rating', style: TextStyle(fontSize: 11, color: Colors.black54)), const SizedBox(height: 2), Stars(l['rating'])]),
      ]),
      if (status == 'pending_approval')
        const Padding(padding: EdgeInsets.only(top: 12), child: Text('Waiting for admin approval before it appears in search.', style: TextStyle(fontSize: 12, color: Color(0xFF8A5B00)))),
      const SizedBox(height: 8),
      Row(children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
          icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit'),
          onPressed: () async {
            final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AddListing(initial: l)));
            if (ok == true) onChanged();
          },
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
          icon: const Icon(Icons.calendar_month_outlined, size: 18), label: const Text('Availability'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AvailabilityScreen(listingId: l['id'], title: l['title']))),
        ),
        const SizedBox(width: 8),
        if (l['allow_offers'] == true) const Chip(avatar: Icon(Icons.handshake_outlined, size: 16), label: Text('Offers on'), visualDensity: VisualDensity.compact),
        if (l['booking_mode'] == 'request') const Chip(avatar: Icon(Icons.how_to_reg_outlined, size: 16), label: Text('Request to book'), visualDensity: VisualDensity.compact),
      ]),
      if (toggleable)
        SwitchListTile(
          contentPadding: EdgeInsets.zero, dense: true,
          title: Text(status == 'live' ? 'Visible in search' : 'Paused (hidden from search)'),
          value: status == 'live',
          onChanged: (v) async {
            try {
              await api.patch('/listings/${l['id']}/status', {'status': v ? 'live' : 'paused'});
              onChanged();
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
            }
          },
        ),
    ])));
  }

  Widget _stat(String k, String v) => Column(children: [
        Text(k, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 2),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);
}

class AddListing extends StatefulWidget {
  const AddListing({super.key, this.initial});
  final Json? initial;

  @override
  State<AddListing> createState() => _AddListingState();
}

class _AddListingState extends State<AddListing> {
  late final Json _i = widget.initial ?? {};
  late final _title = TextEditingController(text: _i['title']);
  late final _address = TextEditingController(text: _i['address']);
  late final _postcode = TextEditingController(text: _i['postcode']);
  late final _hour = TextEditingController(text: _i['price_hour'] == null ? '2.50' : '${num_(_i['price_hour'])}');
  late final _day = TextEditingController(text: _i['price_day'] == null ? '' : '${num_(_i['price_day'])}');
  late final _access = TextEditingController(text: _i['access_instructions']);
  late final _minOffer = TextEditingController(text: _i['min_offer_price'] == null ? '' : '${num_(_i['min_offer_price'])}');
  late String _type = _i['space_type'] ?? 'driveway';
  late String _size = _i['max_vehicle_size'] ?? 'medium';
  late String _policy = _i['cancellation_policy'] ?? 'flexible';
  late String _mode = _i['booking_mode'] ?? 'instant';
  late bool _offers = _i['allow_offers'] == true;
  late int _minStay = _i['min_stay_minutes'] ?? 30;
  late int _maxStayH = ((_i['max_stay_minutes'] ?? 43200) / 60).round();
  late int _buffer = _i['buffer_minutes'] ?? 15;
  late final Set<String> _features = {...((_i['features'] as List?)?.cast<String>() ?? const <String>[])};
  late LatLng _pin = LatLng(num_(_i['latitude'] ?? 51.5308), num_(_i['longitude'] ?? -0.1238));
  bool _busy = false;
  bool get _editing => widget.initial != null;

  Future<void> _submit() async {
    final hour = double.tryParse(_hour.text);
    if (_title.text.trim().length < 3 || _address.text.trim().length < 3 || hour == null) {
      toast(context, 'Please add a title, address and hourly price', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final body = {
        'title': _title.text.trim(), 'address': _address.text.trim(),
        if (_postcode.text.trim().isNotEmpty) 'postcode': _postcode.text.trim(),
        'latitude': _pin.latitude, 'longitude': _pin.longitude,
        'spaceType': _type, 'maxVehicleSize': _size, 'priceHour': hour,
        'priceDay': double.tryParse(_day.text),
        'features': _features.toList(), 'cancellationPolicy': _policy,
        'accessInstructions': _access.text.trim(),
        'bookingMode': _mode, 'allowOffers': _offers,
        'minOfferPrice': _offers ? double.tryParse(_minOffer.text) : null,
        'minStayMinutes': _minStay, 'maxStayMinutes': _maxStayH * 60, 'bufferMinutes': _buffer,
      };
      final api = context.read<AppState>().api;
      if (_editing) {
        await api.patch('/listings/${_i['id']}', body);
      } else {
        await api.post('/listings', body..removeWhere((k, v) => v == null));
      }
      if (!mounted) return;
      if (!_editing) {
        await showDialog(context: context, builder: (c) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
          title: const Text('Submitted for review'),
          content: const Text("Thanks! Once our team approves your space it will appear in search. You'll see its status under My spaces. Next, set when it's available."),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
        ));
      } else {
        toast(context, 'Space updated');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_editing ? 'Edit space' : 'Add a space')),
        body: ListView(children: [
          Centered(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _section('The basics'),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Driveway near Station Road')),
            const SizedBox(height: 12),
            TextField(controller: _address, decoration: const InputDecoration(labelText: 'Full address')),
            const SizedBox(height: 12),
            TextField(controller: _postcode, decoration: const InputDecoration(labelText: 'Postcode')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: _type, decoration: const InputDecoration(labelText: 'Space type'),
                items: const [
                  DropdownMenuItem(value: 'driveway', child: Text('Driveway')), DropdownMenuItem(value: 'garage', child: Text('Garage')),
                  DropdownMenuItem(value: 'bay', child: Text('Private bay')), DropdownMenuItem(value: 'forecourt', child: Text('Forecourt')),
                ],
                onChanged: (v) => setState(() => _type = v!),
              )),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: _size, decoration: const InputDecoration(labelText: 'Max vehicle'),
                items: const [
                  DropdownMenuItem(value: 'small', child: Text('Small')), DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'large', child: Text('Large')), DropdownMenuItem(value: 'van', child: Text('Van')),
                ],
                onChanged: (v) => setState(() => _size = v!),
              )),
            ]),
            _section('Pin the exact spot'),
            const Text('Tap the map to drop the pin on your space.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(height: 220, child: FlutterMap(
                options: MapOptions(initialCenter: _pin, initialZoom: 14, onTap: (_, p) => setState(() => _pin = p)),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.parkspace.app'),
                  MarkerLayer(markers: [Marker(point: _pin, width: 40, height: 40, alignment: Alignment.topCenter, child: const Icon(Icons.location_on, color: brand, size: 40))]),
                ],
              )),
            ),
            _section('Pricing & stay'),
            Row(children: [
              Expanded(child: TextField(controller: _hour, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price per hour', prefixText: '£ '))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _day, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Day rate (optional)', prefixText: '£ '))),
            ]),
            const SizedBox(height: 6),
            const Text('If a stay is long enough, the cheaper day rate is applied automatically. You receive 80% of each booking.', style: TextStyle(fontSize: 12, color: Colors.black45)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: DropdownButtonFormField<int>(
                initialValue: _minStay, decoration: const InputDecoration(labelText: 'Minimum stay'),
                items: const [
                  DropdownMenuItem(value: 30, child: Text('30 min')), DropdownMenuItem(value: 60, child: Text('1 hour')),
                  DropdownMenuItem(value: 120, child: Text('2 hours')), DropdownMenuItem(value: 240, child: Text('4 hours')),
                ],
                onChanged: (v) => setState(() => _minStay = v!),
              )),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<int>(
                initialValue: [12, 24, 72, 168, 720].contains(_maxStayH) ? _maxStayH : 720, decoration: const InputDecoration(labelText: 'Maximum stay'),
                items: const [
                  DropdownMenuItem(value: 12, child: Text('12 hours')), DropdownMenuItem(value: 24, child: Text('1 day')),
                  DropdownMenuItem(value: 72, child: Text('3 days')), DropdownMenuItem(value: 168, child: Text('1 week')), DropdownMenuItem(value: 720, child: Text('30 days')),
                ],
                onChanged: (v) => setState(() => _maxStayH = v!),
              )),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<int>(
                initialValue: [0, 15, 30, 60].contains(_buffer) ? _buffer : 15, decoration: const InputDecoration(labelText: 'Buffer between'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('None')), DropdownMenuItem(value: 15, child: Text('15 min')),
                  DropdownMenuItem(value: 30, child: Text('30 min')), DropdownMenuItem(value: 60, child: Text('1 hour')),
                ],
                onChanged: (v) => setState(() => _buffer = v!),
              )),
            ]),
            _section('How people book'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'instant', icon: Icon(Icons.bolt), label: Text('Instant book')),
                ButtonSegment(value: 'request', icon: Icon(Icons.how_to_reg_outlined), label: Text('Request to book')),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
            const SizedBox(height: 6),
            Text(_mode == 'instant' ? 'Bookings are confirmed immediately.' : 'Drivers\' cards are held, and you have 30 minutes to accept or decline.', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero, value: _offers, onChanged: (v) => setState(() => _offers = v),
              title: const Text('Allow price offers'), subtitle: const Text('Drivers can negotiate; you can accept, decline or counter.'),
            ),
            if (_offers)
              TextField(controller: _minOffer, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Lowest price per hour you would accept', prefixText: '£ ', helperText: 'Offers below this are declined automatically.')),
            _section('Features'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in featureIcons.entries)
                FilterChip(
                  avatar: Icon(e.value.$1, size: 16), label: Text(e.value.$2), selected: _features.contains(e.key),
                  onSelected: (v) => setState(() => v ? _features.add(e.key) : _features.remove(e.key)),
                ),
            ]),
            _section('Policy & access'),
            DropdownButtonFormField<String>(
              initialValue: _policy, decoration: const InputDecoration(labelText: 'Cancellation policy'),
              items: const [
                DropdownMenuItem(value: 'flexible', child: Text('Flexible')), DropdownMenuItem(value: 'moderate', child: Text('Moderate')), DropdownMenuItem(value: 'strict', child: Text('Strict')),
              ],
              onChanged: (v) => setState(() => _policy = v!),
            ),
            const SizedBox(height: 4),
            Text(policyText[_policy]!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(controller: _access, maxLines: 2, decoration: const InputDecoration(labelText: 'Access instructions (shown only after payment)')),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_editing ? 'Save changes' : 'Submit for approval')),
            const SizedBox(height: 30),
          ])),
        ]),
      );

  Widget _section(String t) => Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)));
}
