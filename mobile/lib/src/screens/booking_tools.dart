import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../ui.dart';

/// Picks an image and uploads it; returns its URL path (or null if cancelled).
Future<String?> pickAndUpload(BuildContext context, {ImageSource source = ImageSource.gallery}) async {
  final api = context.read<AppState>().api;
  try {
    final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    final name = f.name.isEmpty ? 'photo.jpg' : f.name;
    final mime = name.toLowerCase().endsWith('.png') ? 'image/png' : name.toLowerCase().endsWith('.webp') ? 'image/webp' : 'image/jpeg';
    return await api.upload(bytes, name, mime);
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
    return null;
  } catch (_) {
    if (context.mounted) toast(context, 'Could not use that photo', error: true);
    return null;
  }
}

/// Best-effort GPS fix for the "I've parked" timestamp. Never blocks the booking if it fails.
Future<Position?> tryLocate() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 6)));
  } catch (_) {
    return null;
  }
}

class ChatCard extends StatefulWidget {
  const ChatCard({super.key, required this.bookingId, required this.canSend, required this.myRole});
  final String bookingId, myRole;
  final bool canSend;

  @override
  State<ChatCard> createState() => _ChatCardState();
}

class _ChatCardState extends State<ChatCard> {
  final _text = TextEditingController();
  List<Json> _msgs = [];
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<AppState>().api.get('/bookings/${widget.bookingId}/messages');
      if (mounted) setState(() => _msgs = (r as List).map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (_) {}
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.post('/bookings/${widget.bookingId}/messages', {'text': t});
      _text.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AppState>().user!['id'];
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.chat_bubble_outline, size: 18), SizedBox(width: 8), Text('Chat', style: TextStyle(fontWeight: FontWeight.w700))]),
      const SizedBox(height: 8),
      if (_msgs.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No messages yet. Say hello or ask about access.', style: TextStyle(color: Colors.black54))),
      for (final m in _msgs)
        Align(
          alignment: m['sender_id'] == me ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: m['sender_id'] == me ? const Color(0xFFDDE7FF) : const Color(0xFFF1F3F8), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m['text']),
              Text('${m['sender_id'] == me ? 'You' : m['sender_name']} · ${fmtTime(dt(m['created_at']))}', style: const TextStyle(fontSize: 10, color: Colors.black45)),
            ]),
          ),
        ),
      if (widget.canSend) Row(children: [
        Expanded(child: TextField(controller: _text, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Write a message', isDense: true))),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.send, size: 18)),
      ]),
    ])));
  }
}

const problemTypes = {
  'space_occupied': "Space occupied / can't access",
  'extra_not_provided': 'Extra not provided',
  'wrong_vehicle': 'Wrong vehicle / someone else parked',
  'damage': 'Damage',
  'driver_overstayed': 'Driver overstayed',
  'other': 'Other',
};

/// Report a problem. For "space occupied" the driver is offered: message host, find alternatives, or a full refund.
/// Returns true if the booking changed.
Future<bool> showReportProblem(BuildContext context, Json b) async {
  final api = context.read<AppState>().api;
  final isDriver = b['viewer'] == 'driver';
  final status = b['status'] as String;
  final types = problemTypes.keys.where((k) => isDriver ? k != 'driver_overstayed' : k != 'space_occupied' && k != 'extra_not_provided').toList();
  String type = types.first;
  String? extraId;
  String? photo;
  final desc = TextEditingController();
  final extras = (b['extras'] as List).cast<Map>();
  String? error;
  bool busy = false;
  var changed = false;

  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: const Text('Report a problem'),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Tell us what went wrong. Payouts for this booking pause until our team decides.", style: TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: type, decoration: const InputDecoration(labelText: 'What happened?'),
          items: [for (final k in types) DropdownMenuItem(value: k, child: Text(problemTypes[k]!))],
          onChanged: (v) => set(() => type = v!),
        ),
        if (type == 'space_occupied' && isDriver && ['confirmed', 'parked'].contains(status)) ...[
          const SizedBox(height: 12),
          const Text('We are sorry. What would you like to do?', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          OutlinedButton.icon(icon: const Icon(Icons.chat_bubble_outline), label: const Text('Message the host'), onPressed: () => Navigator.pop(c)),
          const SizedBox(height: 6),
          OutlinedButton.icon(icon: const Icon(Icons.search), label: const Text('Find a nearby alternative'), onPressed: () {
            Navigator.pop(c);
            Navigator.of(context).popUntil((r) => r.isFirst);
          }),
          const SizedBox(height: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF136C37)),
            icon: const Icon(Icons.replay), label: Text('Get a full refund (${money(b['total_amount'])})'),
            onPressed: busy ? null : () async {
              set(() => busy = true);
              try {
                await api.post('/bookings/${b['id']}/occupied-refund');
                changed = true;
                if (c.mounted) Navigator.pop(c);
              } on ApiException catch (e) {
                set(() { busy = false; error = e.message; });
              }
            },
          ),
        ] else ...[
          if (type == 'extra_not_provided' && extras.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: extraId, decoration: const InputDecoration(labelText: 'Which extra?'),
              items: [for (final x in extras) DropdownMenuItem(value: x['id'] as String, child: Text('${x['name']} (${money(x['line_total'])})'))],
              onChanged: (v) => set(() => extraId = v),
            ),
          ],
          const SizedBox(height: 10),
          TextField(controller: desc, maxLines: 3, maxLength: 1000, decoration: const InputDecoration(labelText: 'Describe the problem')),
          Row(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(photo == null ? 'Add a photo' : 'Photo added'),
              onPressed: () async {
                final u = await pickAndUpload(context);
                if (u != null) set(() => photo = u);
              },
            ),
          ]),
        ],
        if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
        if (!(type == 'space_occupied' && isDriver && ['confirmed', 'parked'].contains(status)))
          FilledButton(
            onPressed: busy ? null : () async {
              if (type == 'extra_not_provided' && extras.isNotEmpty && extraId == null) { set(() => error = 'Choose which extra was not provided'); return; }
              set(() { busy = true; error = null; });
              try {
                await api.post('/bookings/${b['id']}/dispute', {
                  'type': type, if (desc.text.trim().isNotEmpty) 'description': desc.text.trim(),
                  'extraId': ?extraId, if (photo != null) 'photos': [photo],
                });
                changed = true;
                if (c.mounted) Navigator.pop(c);
              } on ApiException catch (e) {
                set(() { busy = false; error = e.message; });
              }
            },
            child: const Text('Submit report'),
          ),
      ],
    )),
  );
  return changed;
}

Future<void> showReceipt(BuildContext context, String bookingId) async {
  final api = context.read<AppState>().api;
  Json r;
  try {
    r = Map<String, dynamic>.from(await api.get('/bookings/$bookingId/receipt'));
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
    return;
  }
  if (!context.mounted) return;
  Widget row(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null))),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        ]),
      );
  final isReceipt = r['kind'] == 'receipt';
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(isReceipt ? 'Receipt' : 'Earnings statement'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${r['title']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        Text('Booking ${r['reference']} · ${fmtRange(r['booked_start'], r['booked_end'])}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
        const Divider(height: 22),
        if (isReceipt) ...[
          for (final l in (r['lines'] as List).cast<Map>()) row('${l['label']}', money(l['amount'])),
          const Divider(height: 18),
          row('Total charged', money(r['paid']), bold: true),
          if (num_(r['refunded']) > 0) row('Refunded', '- ${money(r['refunded'])}'),
          if (num_(r['refunded']) > 0) row('You paid', money(r['net']), bold: true),
        ] else ...[
          row('Booking total', money(r['gross'])),
          row('ParkSpace commission (${(num_(r['commission_rate']) * 100).toStringAsFixed(0)}%)', '- ${money(r['commission'])}'),
          const Divider(height: 18),
          row('Your earnings', money(r['earned']), bold: true),
        ],
        const SizedBox(height: 8),
        const Text('A copy is also emailed to you.', style: TextStyle(fontSize: 12, color: Colors.black45)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
    ),
  );
}

Future<Position?> locateForParking() => tryLocate();
