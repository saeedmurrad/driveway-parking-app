import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'booking_detail.dart';

/// Opens the "make an offer" dialog from a space page. Returns the created thread id (or null).
Future<String?> showMakeOffer(BuildContext context, {
  required String listingId, required String title, required double listedTotal,
  required DateTime start, required DateTime end, String? vehicleId, List<Json> extras = const [],
}) async {
  final amount = TextEditingController();
  final message = TextEditingController();
  String? error;
  bool busy = false;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: const Text('Make an offer'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${fmtRange(start.toUtc().toIso8601String(), end.toUtc().toIso8601String())}\nListed price: ${money(listedTotal)}', style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 14),
        TextField(controller: amount, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Your offer (total)', prefixText: '£ ')),
        const SizedBox(height: 10),
        TextField(controller: message, maxLength: 200, maxLines: 2, decoration: const InputDecoration(labelText: 'Short message (optional)')),
        const Text('Times are fixed once you send. Phone numbers, emails and links are not allowed in messages. The slot is not reserved while you negotiate.', style: TextStyle(fontSize: 12, color: Colors.black45)),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: busy ? null : () async {
            final a = double.tryParse(amount.text.trim());
            if (a == null) { set(() => error = 'Enter an amount'); return; }
            set(() { busy = true; error = null; });
            try {
              final api = context.read<AppState>().api;
              final r = await api.post('/offers', {
                'listingId': listingId, 'vehicleId': ?vehicleId,
                if (extras.isNotEmpty) 'extras': extras,
                'start': start.toUtc().toIso8601String(), 'end': end.toUtc().toIso8601String(),
                'amount': a, if (message.text.trim().isNotEmpty) 'message': message.text.trim(),
              });
              if (c.mounted) Navigator.pop(c, r['offer']['thread_id']);
            } on ApiException catch (e) {
              set(() { busy = false; error = e.message; });
            }
          },
          child: const Text('Send offer'),
        ),
      ],
    )),
  );
}

class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<Json>>(
      load: () async => ((await api.get('/offers')) as List).map((e) => Map<String, dynamic>.from(e)).toList(),
      builder: (context, items, reload) => RefreshIndicator(
        onRefresh: reload,
        child: items.isEmpty
            ? ListView(children: const [SizedBox(height: 420, child: EmptyState(Icons.handshake_outlined, 'No offers yet', subtitle: 'Spaces that allow offers show a "Make an offer" button. Try negotiating a better price.'))])
            : ListView(children: [
                Centered(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Offers', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  for (final o in items)
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: _OfferCard(o: o, onBack: reload)),
                ])),
              ]),
      ),
    );
  }
}

Color _offerColor(String s) => switch (s) {
      'accepted' || 'paid' => const Color(0xFF136C37),
      'declined' || 'expired' => const Color(0xFFA11B1B),
      _ => const Color(0xFF8A5B00),
    };

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.o, required this.onBack});
  final Json o;
  final Future<void> Function() onBack;

  @override
  Widget build(BuildContext context) {
    final status = o['status'] as String;
    final awaiting = o['awaiting_me'] == true;
    final host = o['role'] == 'host';
    final label = awaiting
        ? (status == 'accepted' ? 'Pay now' : 'Your turn')
        : switch (status) { 'open' => 'Waiting for ${host ? 'driver' : 'host'}', 'accepted' => 'Accepted', 'paid' => 'Booked', 'countered' => 'Countered', 'declined' => 'Declined', _ => 'Expired' };
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: awaiting ? brand : const Color(0xFFE6E9F2), width: awaiting ? 2 : 1)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => OfferThreadScreen(threadId: o['thread_id'])));
          await onBack();
        },
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(o['title'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _offerColor(awaiting ? 'open' : status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: TextStyle(color: _offerColor(awaiting ? 'open' : status), fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(fmtRange(o['start_at'], o['end_at'])),
          const SizedBox(height: 4),
          Row(children: [Text(host ? 'Driver: ${o['driver_name']}' : 'Host: ${o['host_name']}', style: const TextStyle(color: Colors.black54, fontSize: 13)), if (host && o['driver_rating'] != null) ...[const SizedBox(width: 6), Stars(o['driver_rating'], size: 14)]]),
          const SizedBox(height: 8),
          Row(children: [
            Text(money(o['amount']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(width: 8),
            Text('listed ${money(o['listed_total'])}', style: const TextStyle(color: Colors.black45, decoration: TextDecoration.lineThrough)),
            const Spacer(),
            Text('${o['steps']} step${o['steps'] == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12, color: Colors.black45)),
          ]),
        ])),
      ),
    );
  }
}

class OfferThreadScreen extends StatefulWidget {
  const OfferThreadScreen({super.key, required this.threadId});
  final String threadId;

  @override
  State<OfferThreadScreen> createState() => _OfferThreadScreenState();
}

class _OfferThreadScreenState extends State<OfferThreadScreen> {
  Json? _t;
  String? _error;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Api get _api => context.read<AppState>().api;

  Future<void> _load() async {
    try {
      final t = await _api.get('/offers/${widget.threadId}');
      if (!mounted) return;
      setState(() {
        _t = Map<String, dynamic>.from(t);
        _error = null;
      });
    } catch (e) {
      if (mounted && _t == null) setState(() => _error = '$e');
    }
  }

  Future<void> _respond(String action, {double? amount, String? message}) async {
    setState(() => _busy = true);
    try {
      final t = await _api.post('/offers/${_t!['current']['id']}/respond', {'action': action, 'amount': ?amount, if (message != null && message.isNotEmpty) 'message': message});
      if (mounted) {
        setState(() => _t = Map<String, dynamic>.from(t));
        toast(context, switch (action) { 'accept' => 'Offer accepted', 'decline' => 'Offer declined', _ => 'Counter-offer sent' });
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _counter() async {
    final amount = TextEditingController();
    final message = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Counter-offer'),
        content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Listed price ${money(_t!['listed_total'])}. Current offer ${money(_t!['current']['amount'])}.', style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          TextField(controller: amount, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Your price', prefixText: '£ ')),
          const SizedBox(height: 10),
          TextField(controller: message, maxLength: 200, decoration: const InputDecoration(labelText: 'Message (optional)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send counter')),
        ],
      ),
    );
    final a = double.tryParse(amount.text.trim());
    if (ok == true && a != null) _respond('counter', amount: a, message: message.text.trim());
  }

  Future<void> _pay() async {
    setState(() => _busy = true);
    try {
      final b = await _api.post('/offers/${_t!['current']['id']}/pay');
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BookingDetail(bookingId: b['id'], justBooked: true)));
    } on ApiException catch (e) {
      if (mounted) {
        toast(context, e.message, error: true);
        _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      appBar: AppBar(title: const Text('Negotiation')),
      body: t == null
          ? (_error != null ? EmptyState(Icons.error_outline, 'Could not load', subtitle: _error) : const Center(child: CircularProgressIndicator()))
          : ListView(children: [Centered(child: _body(context, t))]),
    );
  }

  Widget _body(BuildContext context, Json t) {
    final cur = t['current'] as Json;
    final steps = (t['steps'] as List).cast<Map>();
    final role = t['role'] as String;
    final status = cur['status'] as String;
    final closed = ['declined', 'expired', 'paid'].contains(status);
    final until = status == 'accepted' && cur['pay_by'] != null ? dt(cur['pay_by']) : (status == 'open' ? dt(cur['expires_at']) : null);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t['title'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Row(children: [const Icon(Icons.event, size: 18, color: Colors.black54), const SizedBox(width: 8), Expanded(child: Text(fmtRange(t['start_at'], t['end_at'])))]),
        const SizedBox(height: 6),
        Row(children: [const Icon(Icons.person_outline, size: 18, color: Colors.black54), const SizedBox(width: 8), Text(role == 'host' ? 'Driver: ${t['driver_name']}' : 'Host: ${t['host_name']}')]),
        const Divider(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Listed price', style: TextStyle(fontSize: 12, color: Colors.black54)),
            Text(money(t['listed_total']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, decoration: TextDecoration.lineThrough, color: Colors.black45)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Current ${cur['sent_by'] == 'host' ? 'host' : 'driver'} offer', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            Text(money(cur['amount']), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          ]),
        ]),
      ]))),
      const SizedBox(height: 12),
      if (until != null && !closed)
        _notice(status == 'accepted'
            ? (role == 'driver' ? 'Accepted at ${money(cur['amount'])}. Pay before ${fmtTime(until)} (15 minutes) or the offer lapses.' : 'Accepted. Waiting for the driver to pay (they have until ${fmtTime(until)}).')
            : 'This offer expires at ${fmtTime(until)}.', Icons.timer_outlined, const Color(0xFFFFF0C9), const Color(0xFF8A5B00)),
      if (status == 'declined' && steps.last['decline_reason'] == 'below_minimum')
        _notice('This offer was below the lowest price the host can accept. The listed price is still available.', Icons.info_outline, const Color(0xFFFFDDDD), const Color(0xFFA11B1B)),
      if (status == 'expired') _notice('This negotiation has ended (expired or the time was booked by someone else).', Icons.timer_off_outlined, const Color(0xFFFFDDDD), const Color(0xFFA11B1B)),
      if (status == 'paid') _notice('Paid. This offer became a confirmed booking.', Icons.check_circle_outline, const Color(0xFFD9F5E3), const Color(0xFF136C37)),
      if (t['can_pay'] == true) FilledButton.icon(icon: const Icon(Icons.lock_outline), label: Text('Pay ${money(cur['amount'])} now'), onPressed: _busy ? null : _pay),
      if (t['can_respond'] == true) ...[
        FilledButton.icon(icon: const Icon(Icons.check), label: Text('Accept ${money(cur['amount'])}'), onPressed: _busy ? null : () => _respond('accept')),
        const SizedBox(height: 8),
        Row(children: [
          if (t['can_counter'] == true) Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.swap_horiz), label: const Text('Counter'), onPressed: _busy ? null : _counter)),
          if (t['can_counter'] == true) const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700), icon: const Icon(Icons.close), label: const Text('Decline'),
            onPressed: _busy ? null : () => _respond('decline'))),
        ]),
        if (t['can_counter'] != true) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Final round: the maximum of 3 counter-offers has been reached.', style: TextStyle(fontSize: 12, color: Colors.black54))),
      ],
      if (status == 'open' && t['can_respond'] != true) const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Waiting for the other side to respond.', style: TextStyle(color: Colors.black54))),
      const SizedBox(height: 16),
      const Text('History', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 8),
      for (final s in steps)
        _step(s, role),
    ]);
  }

  Widget _notice(String text, IconData icon, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: fg), const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: fg))),
        ]),
      );

  Widget _step(Map s, String role) {
    final mine = s['sent_by'] == role;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFFDDE7FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6E9F2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${s['sent_by'] == 'host' ? 'Host' : 'Driver'} · round ${s['round']}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
          Text(money(s['amount']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          if (s['message'] != null && '${s['message']}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('"${s['message']}"')),
          const SizedBox(height: 4),
          Text('${fmtFull(s['created_at'])} · ${s['status']}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
        ]),
      ),
    );
  }
}
