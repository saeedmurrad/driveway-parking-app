import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../state.dart';
import '../ui.dart';

class BookingDetail extends StatefulWidget {
  const BookingDetail({super.key, required this.bookingId, this.justBooked = false});
  final String bookingId;
  final bool justBooked;

  @override
  State<BookingDetail> createState() => _BookingDetailState();
}

class _BookingDetailState extends State<BookingDetail> {
  Json? _b;
  String? _error;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Pick up auto-end and other server-side changes.
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final b = await context.read<AppState>().api.get('/bookings/${widget.bookingId}');
      if (!mounted) return;
      setState(() {
        _b = Map<String, dynamic>.from(b);
        _error = null;
      });
    } catch (e) {
      if (mounted && _b == null) setState(() => _error = '$e');
    }
  }

  Future<void> _act(String path, String done, {Object? body}) async {
    setState(() => _busy = true);
    try {
      final b = await context.read<AppState>().api.post('/bookings/${widget.bookingId}/$path', body);
      if (mounted) {
        setState(() => _b = Map<String, dynamic>.from(b));
        toast(context, done);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(Json b) async {
    final q = b['cancel_quote'];
    final isHost = b['viewer'] == 'host';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Text(isHost
            ? 'The driver will get a full refund (${money(q?['amount'])}). Repeated host cancellations can lead to suspension.'
            : q != null && q['percent'] == 0
                ? 'Under the ${b['cancellation_policy']} policy you will not get a refund.'
                : 'You will be refunded ${money(q?['amount'])} (${q?['percent']}%).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep booking')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700), onPressed: () => Navigator.pop(c, true), child: const Text('Cancel booking')),
        ],
      ),
    );
    if (ok == true) _act('cancel', 'Booking cancelled');
  }

  Future<void> _review() async {
    int stars = 5;
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: Text(_b!['viewer'] == 'driver' ? 'Rate this space' : 'Rate this driver'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(onPressed: () => set(() => stars = i), icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFF5A623), size: 34)),
          ]),
          TextField(controller: comment, maxLines: 3, decoration: const InputDecoration(hintText: 'Add a comment (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Submit')),
        ],
      )),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppState>().api.post('/bookings/${widget.bookingId}/review', {'stars': stars, 'comment': comment.text.trim()});
      if (mounted) toast(context, 'Thanks for your review!');
      _load();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    return Scaffold(
      appBar: AppBar(title: Text(b == null ? 'Booking' : 'Booking ${b['reference']}')),
      body: b == null
          ? (_error != null ? EmptyState(Icons.error_outline, 'Could not load booking', subtitle: _error) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(onRefresh: _load, child: _content(context, b)),
    );
  }

  Widget _content(BuildContext context, Json b) {
    final isDriver = b['viewer'] == 'driver';
    final isHost = b['viewer'] == 'host';
    final status = b['status'] as String;
    final start = dt(b['booked_start']), end = dt(b['booked_end']);
    final now = DateTime.now();
    final canPark = status == 'confirmed' && now.isAfter(start.subtract(const Duration(minutes: 15))) && now.isBefore(end);
    final paid = ['confirmed', 'parked', 'overstay', 'completed'].contains(status);
    final events = (b['events'] as List).cast<Map>();

    return ListView(children: [
      Centered(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.justBooked && status == 'confirmed')
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFD9F5E3), borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [
                Icon(Icons.check_circle, color: Color(0xFF136C37)), SizedBox(width: 10),
                Expanded(child: Text("You're booked! Your address and access instructions are below.", style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF136C37)))),
              ]),
            ),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(b['title'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))), StatusChip(status)]),
            const SizedBox(height: 8),
            Row(children: [const Icon(Icons.event, size: 18, color: Colors.black54), const SizedBox(width: 8), Expanded(child: Text(fmtRange(b['booked_start'], b['booked_end'])))]),
            if (b['offer_id'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [const Icon(Icons.handshake_outlined, size: 18, color: Colors.teal), const SizedBox(width: 8), const Text('Negotiated price', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.w600))])),
            if (b['plate'] != null) ...[
              const SizedBox(height: 6),
              Row(children: [const Icon(Icons.directions_car, size: 18, color: Colors.black54), const SizedBox(width: 8), Text('${b['plate']}${b['make'] != null ? ' · ${b['make']} ${b['model'] ?? ''}' : ''}')]),
            ],
            const SizedBox(height: 6),
            Row(children: [const Icon(Icons.person_outline, size: 18, color: Colors.black54), const SizedBox(width: 8), Text(isDriver ? 'Host: ${b['host_name']}' : 'Driver: ${b['driver_name']}')]),
            if (status == 'cancelled' && b['cancel_reason'] != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('Cancelled by ${b['cancelled_by']} · ${b['cancel_reason']}', style: TextStyle(color: Colors.red.shade700))),
          ]))),
          const SizedBox(height: 12),
          if (isDriver && paid && b['address'] != null)
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Where to park', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [const Icon(Icons.place, color: brand), const SizedBox(width: 8), Expanded(child: Text(b['address'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))]),
              if (b['access_instructions'] != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10), width: double.infinity,
                  decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(10)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.key, size: 18), const SizedBox(width: 8), Expanded(child: Text(b['access_instructions']))]),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.directions),
                label: const Text('Open in Maps'),
                onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${b['latitude']},${b['longitude']}'), mode: LaunchMode.externalApplication),
              ),
            ]))),
          if (isDriver && paid && b['address'] != null) const SizedBox(height: 12),
          _actions(context, b, isDriver, isHost, status, canPark, start),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            _kv('Booked', '${fmtTime(start)} – ${fmtTime(end)}'),
            _kv('Parked at', b['actual_parked_at'] == null ? '—' : fmtFull(b['actual_parked_at'])),
            _kv('Left at', b['actual_ended_at'] == null ? '—' : fmtFull(b['actual_ended_at'])),
            const Divider(height: 22),
            _kv('Parking', money(b['parking_amount'])),
            for (final x in (b['extras'] as List).cast<Map>())
              _kv('${x['name']}${x['price_unit'] == 'per_booking' ? '' : ' × ${num_(x['quantity']).toStringAsFixed(0)}'}', money(x['line_total'])),
            if (num_(b['overstay_fee']) > 0) _kv('Overstay fee', money(b['overstay_fee'])),
            _kv('Total paid', money(b['total_amount']), bold: true),
            if (isHost) ...[
              _kv('Platform commission (${(num_(b['commission_rate']) * 100).toStringAsFixed(0)}%)', '- ${money(b['commission_amount'])}'),
              _kv('Your earnings', money(b['host_earnings']), bold: true),
            ],
          ]))),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Timeline', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final e in events)
              Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
                const Icon(Icons.circle, size: 9, color: brand), const SizedBox(width: 10),
                Expanded(child: Text(_eventLabel(e['event']), style: const TextStyle(fontWeight: FontWeight.w500))),
                Text('${fmtFull(e['created_at'])} · ${e['actor']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ])),
          ]))),
        ]),
      ),
    ]);
  }

  Widget _banner(IconData icon, String text, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: fg), const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: fg))),
        ]),
      );

  Future<void> _extend(Json b) async {
    final hours = await showModalBottomSheet<int>(
      context: context, showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Extend your stay', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Currently ends ${fmtTime(dt(b['booked_end']))}. Extra time is charged now at the hourly rate, if the space is free.', style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 14),
          for (final h in [1, 2, 4])
            Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton(
              onPressed: () => Navigator.pop(c, h),
              child: Text('+$h hour${h > 1 ? 's' : ''}  ·  until ${fmtTime(dt(b['booked_end']).add(Duration(hours: h)))}'),
            )),
        ]),
      ),
    );
    if (hours == null) return;
    _act('extend', 'Booking extended', body: {'hours': hours});
  }

  Widget _actions(BuildContext context, Json b, bool isDriver, bool isHost, String status, bool canPark, DateTime start) {
    final children = <Widget>[];
    final end = dt(b['booked_end']);
    final now = DateTime.now();

    // Request-to-book
    if (status == 'requested') {
      final by = b['respond_by'] == null ? null : dt(b['respond_by']);
      if (isHost) {
        children.add(_banner(Icons.how_to_reg_outlined, 'Booking request: accept before ${by == null ? 'the deadline' : fmtTime(by)}. The driver\'s card is on hold and is only charged if you accept.', const Color(0xFFFFF0C9), const Color(0xFF8A5B00)));
        children.add(FilledButton.icon(icon: const Icon(Icons.check), label: const Text('Accept booking'), onPressed: _busy ? null : () => _act('respond', 'Booking accepted', body: {'accept': true})));
        children.add(OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700), icon: const Icon(Icons.close), label: const Text('Decline'),
          onPressed: _busy ? null : () => _act('respond', 'Request declined', body: {'accept': false})));
      } else if (isDriver) {
        children.add(_banner(Icons.hourglass_top, 'Waiting for the host. Your card is on hold and won\'t be charged unless they accept${by == null ? '' : ' (they have until ${fmtTime(by)})'}.', const Color(0xFFFFF0C9), const Color(0xFF8A5B00)));
        children.add(OutlinedButton.icon(icon: const Icon(Icons.undo), label: const Text('Withdraw request'), onPressed: _busy ? null : () => _act('cancel', 'Request withdrawn, no charge')));
      }
    }

    // Overstay prompts
    if (isHost && status == 'parked' && b['overstay_check'] == 'asked') {
      children.add(_banner(Icons.directions_car_outlined, 'This booking has ended. Is the driver\'s car still at your space?', const Color(0xFFFFE3D1), const Color(0xFFB34700)));
      children.add(Row(children: [
        Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF136C37)), onPressed: _busy ? null : () => _act('car-status', 'Thanks, booking closed', body: {'stillThere': false}), child: const Text('The car has gone'))),
        const SizedBox(width: 8),
        Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB34700)), onPressed: _busy ? null : () => _act('car-status', 'Overstay fees now apply', body: {'stillThere': true}), child: const Text('Still there'))),
      ]));
    }
    if (isDriver && status == 'parked' && now.isAfter(end)) {
      children.add(_banner(Icons.timer_outlined, 'Your booking has ended. Please move your car and tap End Booking, or overstay fees may apply.', const Color(0xFFFFE3D1), const Color(0xFFB34700)));
    }
    if (status == 'overstay') {
      children.add(_banner(Icons.warning_amber_rounded,
          '${isDriver ? 'You are overstaying' : 'The driver is overstaying'}: ${money(b['overstay_fee_now'])} so far (${b['overstay_hours']}h × 1.5× hourly rate). The fee stops when the driver ends the booking.',
          const Color(0xFFFFDDDD), const Color(0xFFA11B1B)));
    }

    if (isDriver && status == 'confirmed') {
      children.add(FilledButton.icon(
        icon: const Icon(Icons.local_parking),
        label: Text(canPark ? "I've parked" : "I've parked (from ${fmtTime(start.subtract(const Duration(minutes: 15)))})"),
        onPressed: canPark && !_busy ? () => _act('parked', 'Timestamp saved, enjoy your stay', body: {}) : null,
      ));
    }
    if (isDriver && (status == 'parked' || status == 'overstay')) {
      children.add(FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF136C37)),
        icon: const Icon(Icons.exit_to_app),
        label: Text(status == 'overstay' ? 'End booking and pay overstay fee' : 'End booking (car has left)'),
        onPressed: _busy ? null : () => _act('end', 'Booking ended. Thanks for parking!'),
      ));
    }
    if (isDriver && (status == 'confirmed' || status == 'parked') && now.isBefore(end)) {
      children.add(OutlinedButton.icon(icon: const Icon(Icons.more_time), label: const Text('Extend booking'), onPressed: _busy ? null : () => _extend(b)));
    }
    if ((isDriver || isHost) && status == 'confirmed') {
      children.add(OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
        icon: const Icon(Icons.cancel_outlined),
        label: Text(isHost ? 'Cancel (driver refunded in full)' : 'Cancel booking'),
        onPressed: _busy ? null : () => _cancel(b),
      ));
    }
    if (status == 'completed' && b['reviewed'] != true && b['viewer'] != 'admin') {
      children.add(FilledButton.tonalIcon(icon: const Icon(Icons.star_outline), label: Text(isDriver ? 'Rate this space' : 'Rate this driver'), onPressed: _review));
    }
    if (children.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final c in children) Padding(padding: EdgeInsets.only(bottom: c is Container ? 0 : 8), child: c),
        if (isDriver && status == 'confirmed')
          const Text('Ending early does not give a refund. If you forget to end, the booking auto-ends after a grace period.', style: TextStyle(fontSize: 12, color: Colors.black45)),
      ]),
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text(k, style: TextStyle(color: bold ? null : Colors.black54, fontWeight: bold ? FontWeight.w800 : null))),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        ]),
      );

  String _eventLabel(String e) => switch (e) {
        'created' => 'Booking created',
        'paid' => 'Payment taken',
        'confirmed' => 'Booking confirmed',
        'parked' => 'Driver marked parked',
        'ended' => 'Driver ended booking',
        'auto_ended' => 'Booking auto-ended',
        'cancelled' => 'Booking cancelled',
        'refunded' => 'Refund issued',
        'requested' => 'Request sent to host',
        'accepted' => 'Host accepted',
        'declined' => 'Host declined',
        'expired' => 'Request expired',
        'extended' => 'Booking extended',
        'overstay' => 'Overstay started',
        _ => e,
      };
}
