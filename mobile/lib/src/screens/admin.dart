import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../ui.dart';

class AdminOverview extends StatelessWidget {
  const AdminOverview({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<Json>(
      load: () async => Map<String, dynamic>.from(await api.get('/admin/stats')),
      builder: (context, s, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(children: [
          Centered(maxWidth: 900, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Platform overview', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 700 ? 3 : 2;
              final w = (c.maxWidth - 12 * (cols - 1)) / cols;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: w, child: StatTile(label: 'Gross booking value', value: money(s['gross']), icon: Icons.payments_outlined)),
                SizedBox(width: w, child: StatTile(label: 'Commission earned', value: money(s['commission']), icon: Icons.account_balance, color: Colors.teal)),
                SizedBox(width: w, child: StatTile(label: "Today's bookings", value: '${s['bookings_today']}', icon: Icons.today, color: Colors.indigo)),
                SizedBox(width: w, child: StatTile(label: 'Parked right now', value: '${s['active_now']}', icon: Icons.local_parking, color: Colors.green)),
                SizedBox(width: w, child: StatTile(label: 'Users', value: '${s['users']}', icon: Icons.people_outline, color: Colors.purple)),
                SizedBox(width: w, child: StatTile(label: 'Listings awaiting approval', value: '${s['pending_listings']}', icon: Icons.pending_actions, color: Colors.orange)),
              ]);
            }),
          ])),
        ]),
      ),
    );
  }
}

class AdminListings extends StatelessWidget {
  const AdminListings({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<Json>>(
      load: () async => ((await api.get('/admin/listings')) as List).map((e) => Map<String, dynamic>.from(e)).toList(),
      builder: (context, items, reload) {
        final pending = items.where((l) => l['status'] == 'pending_approval').toList();
        final rest = items.where((l) => l['status'] != 'pending_approval').toList();
        Future<void> set(Json l, String status) async {
          try {
            await api.post('/admin/listings/${l['id']}/status', {'status': status});
            if (context.mounted) toast(context, status == 'live' ? 'Approved — now live' : 'Listing $status');
            reload();
          } on ApiException catch (e) {
            if (context.mounted) toast(context, e.message, error: true);
          }
        }
        Widget tile(Json l, {bool actions = false}) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(l['title'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))), StatusChip(l['status'])]),
          const SizedBox(height: 4),
          Text('${l['address']}, ${l['postcode'] ?? ''}', style: const TextStyle(color: Colors.black54)),
          Text('Host: ${l['host_name']} · ${money(l['price_hour'])}/h · ${l['space_type']}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
          if (actions) ...[
            const SizedBox(height: 10),
            Row(children: [
              FilledButton.icon(onPressed: () => set(l, 'live'), icon: const Icon(Icons.check), label: const Text('Approve')),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: () => set(l, 'rejected'), icon: const Icon(Icons.close), label: const Text('Reject')),
            ]),
          ],
        ])));
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(children: [
            Centered(maxWidth: 900, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Approval queue (${pending.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 8),
              if (pending.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text('All caught up', style: TextStyle(color: Colors.black54)))))
              else for (final l in pending) Padding(padding: const EdgeInsets.only(bottom: 8), child: tile(l, actions: true)),
              const SizedBox(height: 18),
              const Text('All listings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 8),
              for (final l in rest) Padding(padding: const EdgeInsets.only(bottom: 8), child: tile(l)),
            ])),
          ]),
        );
      },
    );
  }
}

class AdminBookings extends StatelessWidget {
  const AdminBookings({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<Json>>(
      load: () async => ((await api.get('/admin/bookings')) as List).map((e) => Map<String, dynamic>.from(e)).toList(),
      builder: (context, items, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(children: [
          Centered(maxWidth: 900, child: Card(child: Column(children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                title: Text('${items[i]['reference']} · ${items[i]['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${items[i]['driver_name']} → ${items[i]['host_name']}\n${fmtRange(items[i]['booked_start'], items[i]['booked_end'])}'),
                isThreeLine: true,
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(money(items[i]['total_amount']), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('fee ${money(items[i]['commission_amount'])}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  StatusChip(items[i]['status']),
                ]),
              ),
            ],
          ]))),
        ]),
      ),
    );
  }
}

class AdminSettings extends StatelessWidget {
  const AdminSettings({super.key});

  static const _labels = {
    'commission_rate': ('Commission rate', 'Fraction taken from each booking, e.g. 0.20 = 20%. Applies to new bookings only.'),
    'grace_minutes': ('Auto-end grace (minutes)', 'Minutes after booked end before an un-ended booking auto-ends.'),
    'dispute_window_minutes': ('Dispute window (minutes)', 'How long host earnings stay pending after a booking ends. Spec default 1440 (24h).'),
    'buffer_minutes': ('Buffer between bookings (minutes)', 'Default gap reserved after every booking.'),
    'min_payout_gbp': ('Minimum payout (£)', 'Smallest balance a host can pay out.'),
  };

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<Json>>(
      load: () async => ((await api.get('/admin/settings')) as List).map((e) => Map<String, dynamic>.from(e)).where((r) => _labels.containsKey(r['key'])).toList(),
      builder: (context, rows, reload) => ListView(children: [
        Centered(maxWidth: 700, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Platform settings', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Changes apply to new bookings. Existing bookings keep the commission rate they were made with.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 14),
          for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 10), child: _SettingRow(row: r, label: _labels[r['key']]!.$1, hint: _labels[r['key']]!.$2, onSaved: reload)),
        ])),
      ]),
    );
  }
}

class _SettingRow extends StatefulWidget {
  const _SettingRow({required this.row, required this.label, required this.hint, required this.onSaved});
  final Json row;
  final String label, hint;
  final Future<void> Function() onSaved;

  @override
  State<_SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<_SettingRow> {
  late final _c = TextEditingController(text: widget.row['value']);

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(widget.hint, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ])),
        const SizedBox(width: 12),
        SizedBox(width: 90, child: TextField(controller: _c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(isDense: true))),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
          onPressed: () async {
            try {
              await context.read<AppState>().api.put('/admin/settings', {'key': widget.row['key'], 'value': _c.text.trim()});
              if (context.mounted) toast(context, '${widget.label} updated');
              widget.onSaved();
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
            }
          },
          child: const Text('Save'),
        ),
      ])));
}
