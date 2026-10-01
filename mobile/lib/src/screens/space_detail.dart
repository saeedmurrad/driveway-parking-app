import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'booking_detail.dart';
import 'offers.dart';

class SpaceDetail extends StatefulWidget {
  const SpaceDetail({super.key, required this.listingId, required this.start, required this.end});
  final String listingId;
  final DateTime start, end;

  @override
  State<SpaceDetail> createState() => _SpaceDetailState();
}

class _SpaceDetailState extends State<SpaceDetail> {
  Json? _l;
  String? _error;
  bool _busy = false;
  final Map<String, int> _picked = {}; // listing_extra id -> kWh quantity (1 for others)

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _extrasParam => _picked.isEmpty ? null : _picked.entries.map((e) => '${e.key}:${e.value}').join(',');

  Future<void> _load() async {
    final s = context.read<AppState>();
    try {
      final l = await s.api.get('/listings/${widget.listingId}', query: {
        'start': widget.start.toUtc().toIso8601String(),
        'end': widget.end.toUtc().toIso8601String(),
        'extras': ?_extrasParam,
        'vehicleId': ?s.vehicle?['id'],
      });
      if (!mounted) return;
      setState(() {
        _l = Map<String, dynamic>.from(l);
        _error = null;
      });
    } on ApiException catch (e) {
      // e.g. an EV-only extra no longer fits the chosen vehicle: drop the picks and retry once.
      if (_picked.isNotEmpty) {
        _picked.clear();
        if (mounted) toast(context, e.message, error: true);
        return _load();
      }
      if (mounted) setState(() => _error = e.message);
    }
  }

  List<Json> get _extraOptions => ((_l?['extras'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();

  bool _evOk(Json x, AppState s) {
    if (x['ev_only'] != true) return true;
    final v = s.vehicle;
    if (v == null || v['is_ev'] != true) return false;
    final need = (x['details'] as Map?)?['connector'];
    return need == null || v['ev_connector'] == null || v['ev_connector'] == need;
  }

  List<Json> get _extraParams => [
        for (final e in _picked.entries) {'id': e.key, if (e.value > 1) 'quantity': e.value},
      ];

  Future<void> _addVehicle() async {
    final plate = TextEditingController();
    String size = 'medium', connector = 'type2';
    bool isEv = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: const Text('Add your vehicle'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: plate, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Number plate')),
          const SizedBox(height: 12),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Electric vehicle'), value: isEv, onChanged: (v) => set(() => isEv = v)),
          if (isEv) DropdownButtonFormField<String>(
            initialValue: connector, decoration: const InputDecoration(labelText: 'Charging connector'),
            items: const [DropdownMenuItem(value: 'type2', child: Text('Type 2')), DropdownMenuItem(value: 'ccs', child: Text('CCS')), DropdownMenuItem(value: 'chademo', child: Text('CHAdeMO'))],
            onChanged: (v) => set(() => connector = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: size,
            decoration: const InputDecoration(labelText: 'Size'),
            items: const [
              DropdownMenuItem(value: 'small', child: Text('Small')),
              DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'large', child: Text('Large')),
              DropdownMenuItem(value: 'van', child: Text('Van')),
            ],
            onChanged: (v) => set(() => size = v!),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      )),
    );
    if (ok != true || plate.text.trim().length < 2 || !mounted) return;
    final s = context.read<AppState>();
    try {
      final v = await s.api.post('/me/vehicles', {'plate': plate.text.trim(), 'size': size, 'isEv': isEv, if (isEv) 'evConnector': connector});
      await s.loadVehicles();
      s.selectVehicle(v['id']);
      _picked.clear();
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _offer(Json l) async {
    final s = context.read<AppState>();
    final thread = await showMakeOffer(context,
        listingId: widget.listingId, title: l['title'], listedTotal: num_(l['quote']['total']),
        start: widget.start, end: widget.end, vehicleId: s.vehicle?['id'], extras: _extraParams);
    if (thread == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => OfferThreadScreen(threadId: thread)));
  }

  Future<void> _book(Json l) async {
    final s = context.read<AppState>();
    final q = l['quote'];
    final ok = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _Checkout(title: l['title'], quote: q, start: widget.start, end: widget.end, plate: s.vehicle?['plate']),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final created = await s.api.post('/bookings', {
        'listingId': widget.listingId,
        if (s.vehicle != null) 'vehicleId': s.vehicle!['id'],
        'start': widget.start.toUtc().toIso8601String(),
        'end': widget.end.toUtc().toIso8601String(),
        if (_picked.isNotEmpty) 'extras': _extraParams,
      });
      final id = created['booking']['id'];
      await s.api.post('/bookings/$id/pay');
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BookingDetail(bookingId: id, justBooked: true)));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Space details')),
      body: Builder(
        builder: (context) {
          if (_error != null) return EmptyState(Icons.error_outline, 'Could not load this space', subtitle: _error);
          if (_l == null) return const Center(child: CircularProgressIndicator());
          final l = _l!;
          final q = l['quote'];
          final feats = (l['features'] as List).cast<String>();
          final hours = (widget.end.difference(widget.start).inMinutes / 60).ceil();
          return Stack(children: [
            ListView(padding: EdgeInsets.zero, children: [
              _Gallery(photos: (l['photos'] as List).cast<Map>(), fallbackIcon: spaceIcons[l['space_type']] ?? Icons.local_parking),
              Transform.translate(offset: const Offset(0, -26), child: Container(
                decoration: const BoxDecoration(color: Color(0xFFF5F6FB), borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
                child: Centered(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 110),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l['title'], style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.15)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Stars(l['rating'], size: 18),
                    Text('${(l['review_count'] as int) > 0 ? '  (${l['review_count']} reviews)' : ''}  ·  Hosted by ${l['host_name']}', style: const TextStyle(color: Colors.black54)),
                  ]),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Chip(avatar: Icon(spaceIcons[l['space_type']] ?? Icons.local_parking, size: 16), label: Text(_cap(l['space_type']))),
                    Chip(avatar: const Icon(Icons.directions_car, size: 16), label: Text('Fits up to ${l['max_vehicle_size']}')),
                    for (final f in feats) Chip(avatar: Icon(featureIcons[f]?.$1 ?? Icons.check, size: 16), label: Text(featureIcons[f]?.$2 ?? f)),
                  ]),
                  const SizedBox(height: 16),
                  Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Your booking', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Row(children: [const Icon(Icons.event, size: 18, color: Colors.black54), const SizedBox(width: 8), Expanded(child: Text(fmtRange(widget.start.toUtc().toIso8601String(), widget.end.toUtc().toIso8601String())))]),
                    const SizedBox(height: 10),
                    _vehicleRow(s),
                  ]))),
                  if (_extraOptions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _extrasCard(s),
                  ],
                  const SizedBox(height: 12),
                  Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
                    _row('${money(l['price_hour'])} × $hours hour${hours == 1 ? '' : 's'}', money(q['parking'])),
                    for (final x in (q['extras'] as List).cast<Map>())
                      Padding(padding: const EdgeInsets.only(top: 6), child: _row('${x['name']}${x['price_unit'] == 'per_booking' ? '' : ' × ${num_(x['quantity']).toStringAsFixed(0)}${x['price_unit'] == 'per_kwh' ? ' kWh' : ''}'}', money(x['line_total']))),
                    if (num_(q['parking']) < num_(l['price_hour']) * hours)
                      const Padding(padding: EdgeInsets.only(top: 4), child: Align(alignment: Alignment.centerLeft, child: Text('Day rate applied — cheaper than hourly', style: TextStyle(fontSize: 12, color: Colors.green)))),
                    const SizedBox(height: 6),
                    _row('Service fee', '£0.00'),
                    const Divider(height: 22),
                    _row('Total', money(q['total']), bold: true),
                  ]))),
                  if (l['booking_mode'] == 'request') ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFFF0C9), borderRadius: BorderRadius.circular(12)),
                      child: const Row(children: [
                        Icon(Icons.how_to_reg_outlined, color: Color(0xFF8A5B00)), SizedBox(width: 10),
                        Expanded(child: Text("Request to book: the host approves each booking. Your card is held, not charged, until they accept (usually within 30 minutes).", style: TextStyle(color: Color(0xFF8A5B00), fontWeight: FontWeight.w600))),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [Icon(Icons.lock_outline, size: 18), SizedBox(width: 8), Text('Address shared after payment', style: TextStyle(fontWeight: FontWeight.w700))]),
                    const SizedBox(height: 6),
                    Text('Area: ${l['postcode'] ?? 'London'}. You\'ll get the exact address, directions and access instructions as soon as you pay.', style: const TextStyle(color: Colors.black54)),
                    const Divider(height: 22),
                    const Row(children: [Icon(Icons.policy_outlined, size: 18), SizedBox(width: 8), Text('Cancellation', style: TextStyle(fontWeight: FontWeight.w700))]),
                    const SizedBox(height: 6),
                    Text(policyText[l['cancellation_policy']] ?? '', style: const TextStyle(color: Colors.black54)),
                    const Text('Cancel within 5 minutes of booking for a full refund.', style: TextStyle(color: Colors.black54)),
                  ]))),
                  if ((l['reviews'] as List).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Reviews', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    for (final r in l['reviews'] as List)
                      ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(child: Icon(Icons.person, size: 18)),
                        title: Row(children: [Text(r['name']), const SizedBox(width: 8), Stars(r['stars'], size: 14)]), subtitle: Text(r['comment'] ?? '')),
                  ],
                ]),
              ))),
            ]),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Material(
                elevation: 12,
                color: Colors.white,
                child: SafeArea(top: false, child: Centered(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(money(q['total']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      Text('total for $hours h', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ]),
                    const SizedBox(width: 20),
                    if (l['allow_offers'] == true) ...[
                      Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _offer(l), child: const Text('Make an offer'))),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: FilledButton(
                      onPressed: _busy ? null : () => _book(l),
                      child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(l['booking_mode'] == 'request' ? 'Request to book' : 'Book now'),
                    )),
                  ]),
                )),
              ),
            ),
          ]);
        },
      ),
    );
  }

  String _unitLabel(Json x) => switch (x['price_unit']) {
        'per_hour' => '/hour', 'per_day' => '/day', 'per_kwh' => '/kWh', _ => ' flat',
      };

  Widget _extrasCard(AppState s) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Add extras', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        for (final x in _extraOptions) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero, dense: true,
            value: _picked.containsKey(x['id']),
            onChanged: _evOk(x, s) ? (v) {
              setState(() => v == true ? _picked[x['id']] = x['price_unit'] == 'per_kwh' ? 10 : 1 : _picked.remove(x['id']));
              _load();
            } : null,
            title: Row(children: [
              Icon(x['name'] == 'EV charging' ? Icons.ev_station : x['name'].toString().contains('CCTV') ? Icons.videocam_outlined : Icons.add_circle_outline, size: 18, color: Colors.black54),
              const SizedBox(width: 8),
              Expanded(child: Text(x['name'])),
            ]),
            subtitle: Text(
              '${money(x['price'])}${_unitLabel(x)}${x['details'] is Map && (x['details'] as Map)['kw'] != null ? ' · ${(x['details'] as Map)['kw']} kW ${(x['details'] as Map)['connector']}' : ''}'
              '${_evOk(x, s) ? '' : '\nNeeds an electric vehicle with a matching connector. Add one in your profile.'}'),
          ),
          if (_picked.containsKey(x['id']) && x['price_unit'] == 'per_kwh')
            Padding(padding: const EdgeInsets.only(left: 16, bottom: 6), child: Row(children: [
              const Text('Estimated kWh:'),
              const SizedBox(width: 8),
              for (final kwh in [10, 20, 40])
                Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
                  label: Text('$kwh'), selected: _picked[x['id']] == kwh,
                  onSelected: (_) { setState(() => _picked[x['id']] = kwh); _load(); })),
            ])),
        ],
      ])));

  Widget _vehicleRow(AppState s) {
    if (s.vehicles.isEmpty) {
      return Row(children: [
        const Icon(Icons.directions_car, size: 18, color: Colors.black54), const SizedBox(width: 8),
        const Expanded(child: Text('No vehicle saved yet')),
        OutlinedButton(onPressed: _addVehicle, child: const Text('Add vehicle')),
      ]);
    }
    return Row(children: [
      const Icon(Icons.directions_car, size: 18, color: Colors.black54), const SizedBox(width: 8),
      Expanded(child: DropdownButton<String>(
        isExpanded: true, underline: const SizedBox(), value: s.vehicle?['id'],
        items: [for (final v in s.vehicles) DropdownMenuItem(value: v['id'] as String, child: Text('${v['plate']} · ${v['make'] ?? ''} ${v['model'] ?? v['size']}'.trim()))],
        onChanged: (v) { s.selectVehicle(v!); _picked.removeWhere((k, _) => _extraOptions.any((x) => x['id'] == k && x['ev_only'] == true)); _load(); },
      )),
      TextButton(onPressed: _addVehicle, child: const Text('Add')),
    ]);
  }

  Widget _row(String a, String b, {bool bold = false}) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null, fontSize: bold ? 16 : null)),
        Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 16 : null)),
      ]);

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Checkout extends StatelessWidget {
  const _Checkout({required this.title, required this.quote, required this.start, required this.end, required this.plate});
  final String title;
  final Json quote;
  final DateTime start, end;
  final String? plate;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Confirm & pay', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 14),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event), title: Text(fmtRange(start.toUtc().toIso8601String(), end.toUtc().toIso8601String()))),
          if (plate != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.directions_car), title: Text(plate!)),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF4F6FB), borderRadius: BorderRadius.circular(12)),
            child: const Row(children: [
              Icon(Icons.credit_card), SizedBox(width: 10),
              Expanded(child: Text('Visa •••• 4242')),
              Text('TEST CARD', style: TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 6),
          const Text('Demo mode: payment is simulated. Stripe test mode plugs in here.', style: TextStyle(fontSize: 12, color: Colors.black45)),
          const SizedBox(height: 14),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Pay ${money(quote['total'])}')),
        ]),
      );
}

class _Gallery extends StatefulWidget {
  const _Gallery({required this.photos, required this.fallbackIcon});
  final List<Map> photos;
  final IconData fallbackIcon;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) {
      return Container(
        height: 180,
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1234A8), Color(0xFF2D6BFF)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Center(child: Icon(widget.fallbackIcon, size: 84, color: Colors.white.withValues(alpha: 0.9))),
      );
    }
    return SizedBox(
      height: 240,
      child: Stack(children: [
        PageView.builder(
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => Image.network(mediaUrl(widget.photos[i]['url']), fit: BoxFit.cover, width: double.infinity,
              errorBuilder: (_, _, _) => Container(color: const Color(0xFFDDE7FF), child: Icon(widget.fallbackIcon, size: 60, color: brand))),
        ),
        if (widget.photos.length > 1)
          Positioned(
            bottom: 10, left: 0, right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < widget.photos.length; i++)
                Container(margin: const EdgeInsets.symmetric(horizontal: 3), width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: i == _i ? Colors.white : Colors.white54)),
            ]),
          ),
      ]),
    );
  }
}
