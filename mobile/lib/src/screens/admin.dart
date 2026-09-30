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
                SizedBox(width: w, child: StatTile(label: 'Open disputes', value: '${s['open_disputes']}', icon: Icons.gavel, color: Colors.red)),
                SizedBox(width: w, child: StatTile(label: 'Low-rated users', value: '${s['low_rated']}', icon: Icons.star_half, color: Colors.deepOrange, hint: 'Rated under 3 stars')),
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
          if (actions) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 8, children: [
            Chip(visualDensity: VisualDensity.compact, avatar: Icon(l['host_verification'] == 'verified' ? Icons.verified_user : Icons.warning_amber, size: 16, color: l['host_verification'] == 'verified' ? Colors.green : Colors.orange), label: Text('Host ${l['host_verification']}')),
            Chip(visualDensity: VisualDensity.compact, avatar: Icon(l['permission_declared_at'] != null ? Icons.task_alt : Icons.help_outline, size: 16), label: Text(l['permission_declared_at'] != null ? 'Right-to-let declared' : 'No declaration')),
            if (l['host_verification'] != 'verified')
              ActionChip(visualDensity: VisualDensity.compact, label: const Text('Verify host'), onPressed: () async {
                await api.post('/admin/users/${l['host_id']}/verify');
                reload();
              }),
          ])),
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
                onTap: () => _actions(context, items[i], reload),
                title: Text('${items[i]['reference']} · ${items[i]['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${items[i]['driver_name']} → ${items[i]['host_name']}${items[i]['plate'] != null ? ' · ${items[i]['plate']}' : ''}\n${fmtRange(items[i]['booked_start'], items[i]['booked_end'])}'),
                isThreeLine: true,
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(money(items[i]['total_amount']), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(num_(items[i]['refunded']) > 0 ? 'refunded ${money(items[i]['refunded'])}' : 'fee ${money(items[i]['commission_amount'])}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  StatusChip(items[i]['status']),
                ]),
              ),
            ],
          ]))),
        ]),
      ),
    );
  }

  Future<void> _actions(BuildContext context, Json b, Future<void> Function() reload) async {
    final api = context.read<AppState>().api;
    final status = b['status'] as String;
    final canRefund = status == 'completed' || status == 'cancelled';
    final canEnd = ['confirmed', 'parked', 'overstay'].contains(status);
    final amount = TextEditingController();
    final reason = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Booking ${b['reference']}'),
        content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${b['title']}\n${b['driver_name']} → ${b['host_name']}\nTotal ${money(b['total_amount'])} · commission ${(num_(b['commission_rate']) * 100).toStringAsFixed(0)}% · refunded ${money(b['refunded'])}', style: const TextStyle(color: Colors.black54)),
          if (canRefund) ...[
            const SizedBox(height: 14),
            const Text('Issue a refund', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', prefixText: '£ ', isDense: true)),
            const SizedBox(height: 8),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (shown to the driver)', isDense: true)),
            const SizedBox(height: 4),
            const Text('Commission and host earnings are reduced in proportion.', style: TextStyle(fontSize: 12, color: Colors.black45)),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
          if (canEnd) OutlinedButton(onPressed: () async {
            try {
              await api.post('/admin/bookings/${b['id']}/force-end');
              if (c.mounted) Navigator.pop(c);
              if (context.mounted) toast(context, 'Booking ended');
              await reload();
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
            }
          }, child: const Text('Force-end')),
          if (canRefund) FilledButton(onPressed: () async {
            try {
              await api.post('/admin/bookings/${b['id']}/refund', {'amount': double.tryParse(amount.text) ?? 0, 'reason': reason.text.trim()});
              if (c.mounted) Navigator.pop(c);
              if (context.mounted) toast(context, 'Refund issued');
              await reload();
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
            }
          }, child: const Text('Refund')),
        ],
      ),
    );
  }
}

class AdminDisputes extends StatelessWidget {
  const AdminDisputes({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<Json>>(
      load: () async => ((await api.get('/admin/disputes')) as List).map((e) => Map<String, dynamic>.from(e)).toList(),
      builder: (context, items, reload) => RefreshIndicator(
        onRefresh: reload,
        child: items.isEmpty
            ? ListView(children: const [SizedBox(height: 400, child: EmptyState(Icons.gavel, 'No disputes', subtitle: 'Reported problems show up here with the evidence.'))])
            : ListView(children: [
                Centered(maxWidth: 900, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Disputes', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  for (final d in items)
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => DisputeScreen(id: d['id'])));
                        reload();
                      },
                      title: Text('${d['reference']} · ${'${d['type']}'.replaceAll('_', ' ')}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${d['title']}\nReported by ${d['opened_by_name']} (${d['by_driver'] == true ? 'driver' : 'host'}) · ${fmtFull(d['created_at'])}'),
                      isThreeLine: true,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: d['status'] == 'resolved' ? const Color(0xFFD9F5E3) : const Color(0xFFFFF0C9), borderRadius: BorderRadius.circular(20)),
                        child: Text('${d['status']}'.replaceAll('_', ' '), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: d['status'] == 'resolved' ? const Color(0xFF136C37) : const Color(0xFF8A5B00))),
                      ),
                    ))),
                ])),
              ]),
      ),
    );
  }
}

class DisputeScreen extends StatefulWidget {
  const DisputeScreen({super.key, required this.id});
  final String id;

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> {
  Json? _d;

  Future<void> _load() async {
    final d = await context.read<AppState>().api.get('/admin/disputes/${widget.id}');
    if (mounted) setState(() => _d = Map<String, dynamic>.from(d));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _resolve() async {
    final d = _d!;
    final amount = TextEditingController(text: d['extra'] != null ? '${num_(d['extra']['line_total'])}' : '');
    final note = TextEditingController();
    String decision = 'refund';
    String? userAction;
    String? error;
    final api = context.read<AppState>().api;
    final done = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: const Text('Resolve dispute'),
        content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'refund', label: Text('Refund')), ButtonSegment(value: 'reject', label: Text('No refund'))],
            selected: {decision}, onSelectionChanged: (v) => set(() => decision = v.first),
          ),
          if (decision == 'refund') ...[
            const SizedBox(height: 10),
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Refund amount', prefixText: '£ ', helperText: d['extra'] != null ? 'Extra-only refund: up to ${money(d['extra']['line_total'])}' : 'Booking total ${money(d['total_amount'])}, already refunded ${money(d['refunded'])}')),
          ],
          const SizedBox(height: 10),
          TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Decision note (sent to both users)')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: userAction, decoration: const InputDecoration(labelText: 'Action on a user (optional)'),
            items: const [
              DropdownMenuItem(value: null, child: Text('None')),
              DropdownMenuItem(value: 'warn_host', child: Text('Warn host')), DropdownMenuItem(value: 'warn_driver', child: Text('Warn driver')),
              DropdownMenuItem(value: 'suspend_host', child: Text('Suspend host')), DropdownMenuItem(value: 'suspend_driver', child: Text('Suspend driver')),
            ],
            onChanged: (v) => set(() => userAction = v),
          ),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600))),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            try {
              await api.post('/admin/disputes/${widget.id}/resolve', {
                'decision': decision, if (decision == 'refund') 'amount': double.tryParse(amount.text) ?? 0, 'note': note.text.trim(), 'userAction': ?userAction,
              });
              if (c.mounted) Navigator.pop(c, true);
            } on ApiException catch (e) {
              set(() => error = e.message);
            }
          }, child: const Text('Resolve')),
        ],
      )),
    );
    if (done == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: const Text('Dispute')),
      body: d == null ? const Center(child: CircularProgressIndicator()) : ListView(children: [
        Centered(maxWidth: 800, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d['reference']} · ${'${d['type']}'.replaceAll('_', ' ')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text('${d['title']}\n${d['driver_name']} (driver) → ${d['host_name']} (host)\n${fmtRange(d['booked_start'], d['booked_end'])}', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            Text('Total ${money(d['total_amount'])} · refunded so far ${money(d['refunded'])} · booking ${d['booking_status']}'),
            const Divider(height: 22),
            const Text('Report', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(d['description'] ?? '(no description)'),
            if (d['extra'] != null) Text('Extra: ${d['extra']['name']} (${money(d['extra']['line_total'])})', style: const TextStyle(color: Colors.black54)),
            if (d['photos'] != null && (d['photos'] as List).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 8, children: [
              for (final p in (d['photos'] as List)) ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(mediaUrl('$p'), width: 120, height: 90, fit: BoxFit.cover)),
            ])),
            if (d['status'] == 'resolved') ...[
              const Divider(height: 22),
              Text('Resolved: ${d['resolution']}${d['refund_amount'] != null ? ' (refund ${money(d['refund_amount'])})' : ''}', style: const TextStyle(color: Color(0xFF136C37), fontWeight: FontWeight.w700)),
            ],
          ]))),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Chat log', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if ((d['messages'] as List).isEmpty) const Text('No messages', style: TextStyle(color: Colors.black54)),
            for (final m in (d['messages'] as List).cast<Map>()) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${m['sender']} (${fmtTime(dt(m['created_at']))}): ${m['text']}')),
            const Divider(height: 22),
            const Text('Timeline', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final e in (d['events'] as List).cast<Map>()) Text('${fmtFull(e['created_at'])} · ${e['event']} (${e['actor']})', style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ]))),
          const SizedBox(height: 12),
          if (d['status'] != 'resolved') Row(children: [
            if (d['status'] == 'open') Expanded(child: OutlinedButton(onPressed: () async { await context.read<AppState>().api.post('/admin/disputes/${widget.id}/review'); _load(); }, child: const Text('Start review'))),
            if (d['status'] == 'open') const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: _resolve, child: const Text('Resolve'))),
          ]),
        ])),
      ]),
    );
  }
}

class AdminManage extends StatelessWidget {
  const AdminManage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 5,
        child: Column(children: [
          Container(color: Colors.white, child: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Users'), Tab(text: 'Settings'), Tab(text: 'Content'), Tab(text: 'Announce'), Tab(text: 'Audit log'),
          ])),
          const Expanded(child: TabBarView(children: [_AdminUsers(), AdminSettings(), _AdminContent(), _AdminAnnounce(), _AdminAudit()])),
        ]),
      );
}

class _AdminUsers extends StatefulWidget {
  const _AdminUsers();

  @override
  State<_AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<_AdminUsers> {
  final _q = TextEditingController();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: TextField(
        controller: _q, onSubmitted: (v) => setState(() => _query = v.trim()),
        decoration: InputDecoration(hintText: 'Search name or email', prefixIcon: const Icon(Icons.search), isDense: true, suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => setState(() => _query = _q.text.trim()))),
      )),
      Expanded(child: Loader<List<Json>>(
        key: ValueKey(_query),
        load: () async => ((await api.get('/admin/users', query: {if (_query.isNotEmpty) 'q': _query})) as List).map((e) => Map<String, dynamic>.from(e)).toList(),
        builder: (context, users, reload) => ListView(children: [
          Centered(maxWidth: 900, child: Card(child: Column(children: [
            for (var i = 0; i < users.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                title: Row(children: [
                  Flexible(child: Text(users[i]['name'], style: const TextStyle(fontWeight: FontWeight.w700))),
                  const SizedBox(width: 6),
                  if (users[i]['is_admin'] == true) const Chip(label: Text('Admin'), visualDensity: VisualDensity.compact),
                  if (users[i]['is_host'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Chip(label: Text('Host'), visualDensity: VisualDensity.compact)),
                ]),
                subtitle: Text('${users[i]['email']}\n${users[i]['bookings']} bookings · ${users[i]['email_verified'] == true && users[i]['phone_verified'] == true ? 'contact verified' : 'contact NOT verified'} · ID ${users[i]['verification_status']}'
                    '${users[i]['rating_as_driver'] != null ? ' · driver ★${num_(users[i]['rating_as_driver']).toStringAsFixed(1)}' : ''}${users[i]['rating_as_host'] != null ? ' · host ★${num_(users[i]['rating_as_host']).toStringAsFixed(1)}' : ''}'),
                isThreeLine: true,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (users[i]['verification_status'] != 'verified') TextButton(onPressed: () async { await api.post('/admin/users/${users[i]['id']}/verify'); reload(); }, child: const Text('Verify')),
                  if (users[i]['account_status'] == 'deleted') const Text('Deleted', style: TextStyle(color: Colors.black45))
                  else if (users[i]['is_admin'] != true) OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: users[i]['account_status'] == 'suspended' ? Colors.green : Colors.red.shade700),
                    onPressed: () async {
                      try {
                        await api.post('/admin/users/${users[i]['id']}/status', {'status': users[i]['account_status'] == 'suspended' ? 'active' : 'suspended'});
                        reload();
                      } on ApiException catch (e) {
                        if (context.mounted) toast(context, e.message, error: true);
                      }
                    },
                    child: Text(users[i]['account_status'] == 'suspended' ? 'Reinstate' : 'Suspend'),
                  ),
                ]),
              ),
            ],
          ]))),
        ]),
      )),
    ]);
  }
}

class _AdminContent extends StatelessWidget {
  const _AdminContent();

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<Json>>(
      load: () async => ((await api.get('/content')) as List).map((e) => Map<String, dynamic>.from(e)).toList(),
      builder: (context, items, reload) => ListView(children: [
        Centered(maxWidth: 700, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Terms, Privacy Policy and FAQs are shown in the app. Editing bumps the version.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 10),
          for (final c in items)
            Card(child: ListTile(
              title: Text(c['title'], style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Version ${c['version']}'),
              trailing: OutlinedButton(onPressed: () async {
                final full = await api.get('/content/${c['key']}');
                final body = TextEditingController(text: full['body']);
                if (!context.mounted) return;
                final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                  title: Text('Edit ${c['title']}'),
                  content: SizedBox(width: 560, child: TextField(controller: body, maxLines: 14, decoration: const InputDecoration(alignLabelWithHint: true))),
                  actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Publish'))],
                ));
                if (ok == true) {
                  await api.put('/admin/content/${c['key']}', {'body': body.text});
                  reload();
                }
              }, child: const Text('Edit')),
            )),
        ])),
      ]),
    );
  }
}

class _AdminAnnounce extends StatefulWidget {
  const _AdminAnnounce();

  @override
  State<_AdminAnnounce> createState() => _AdminAnnounceState();
}

class _AdminAnnounceState extends State<_AdminAnnounce> {
  final _title = TextEditingController(), _body = TextEditingController();

  @override
  Widget build(BuildContext context) => ListView(children: [
        Centered(maxWidth: 600, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Push announcement', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const Text('Sent to every active user and shown in their notifications.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 14),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 10),
          TextField(controller: _body, maxLines: 4, decoration: const InputDecoration(labelText: 'Message')),
          const SizedBox(height: 14),
          FilledButton.icon(icon: const Icon(Icons.campaign_outlined), label: const Text('Send to all users'), onPressed: () async {
            try {
              final r = await context.read<AppState>().api.post('/admin/announce', {'title': _title.text, 'body': _body.text});
              if (context.mounted) toast(context, 'Sent to ${r['sent']} users');
              _title.clear();
              _body.clear();
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
            }
          }),
        ])),
      ]);
}

class _AdminAudit extends StatelessWidget {
  const _AdminAudit();

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<Json>>(
      load: () async => ((await api.get('/admin/audit')) as List).map((e) => Map<String, dynamic>.from(e)).toList(),
      builder: (context, rows, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(children: [
          Centered(maxWidth: 900, child: Card(child: Column(children: [
            if (rows.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No admin actions yet')),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.history, size: 20),
                title: Text('${rows[i]['action']}${rows[i]['target'] != null ? ' · ${'${rows[i]['target']}'.length > 12 ? '${rows[i]['target']}'.substring(0, 8) : rows[i]['target']}' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${rows[i]['admin_name']} · ${fmtFull(rows[i]['created_at'])}${rows[i]['details'] != null && '${rows[i]['details']}' != '{}' ? '\n${rows[i]['details']}' : ''}'),
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
    'overstay_multiplier': ('Overstay fee multiplier', 'Fee per extra hour started = this × the hourly rate. Spec default 1.5.'),
    'overstay_response_minutes': ('Host response time for car check (minutes)', 'If the host does not answer "is the car still there?" in this time, the booking auto-ends with no fee.'),
    'request_response_minutes': ('Request-to-book response time (minutes)', 'How long a host has to accept before the card hold is released.'),
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
          const SizedBox(height: 18),
          const _ExtraTypesAdmin(),
          const SizedBox(height: 30),
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

class _ExtraTypesAdmin extends StatelessWidget {
  const _ExtraTypesAdmin();

  Future<void> _add(BuildContext context, Future<void> Function() reload) async {
    final name = TextEditingController(), desc = TextEditingController();
    final units = <String>{'per_booking'};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: const Text('New extra type'),
        content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name, e.g. Bike rack')),
          const SizedBox(height: 10),
          TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description')),
          const SizedBox(height: 10),
          const Text('Hosts can charge it:'),
          Wrap(spacing: 8, children: [
            for (final u in const ['per_booking', 'per_hour', 'per_day', 'per_kwh'])
              FilterChip(label: Text(u.replaceFirst('per_', 'per ')), selected: units.contains(u), onSelected: (v) => set(() => v ? units.add(u) : units.remove(u))),
          ]),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
        ],
      )),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    try {
      await context.read<AppState>().api.post('/admin/extra-types', {'name': name.text.trim(), 'description': desc.text.trim(), 'allowedPriceUnits': units.toList()});
      await reload();
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<Json>>(
      load: () async => ((await api.get('/admin/extra-types')) as List).map((e) => Map<String, dynamic>.from(e)).toList(),
      builder: (context, types, reload) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Paid extras catalogue', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
          FilledButton.tonalIcon(onPressed: () => _add(context, reload), icon: const Icon(Icons.add), label: const Text('Add type')),
        ]),
        const SizedBox(height: 4),
        const Text('New types appear for hosts immediately, no app update needed.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 8),
        Card(child: Column(children: [
          for (final t in types)
            SwitchListTile(
              value: t['active'] == true,
              title: Text(t['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${(t['allowed_price_units'] as List).join(', ').replaceAll('per_', '')}${t['ev_only'] == true ? ' · EV only' : ''}'),
              onChanged: (v) async {
                await api.patch('/admin/extra-types/${t['id']}', {'active': v});
                await reload();
              },
            ),
        ])),
      ]),
    );
  }
}
