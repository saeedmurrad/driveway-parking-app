import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../download.dart';
import '../state.dart';
import '../ui.dart';

class HostEarnings extends StatelessWidget {
  const HostEarnings({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<Json>(
      load: () async => Map<String, dynamic>.from(await api.get('/me/host-summary')),
      builder: (context, s, reload) {
        final canPay = num_(s['available']) >= num_(s['minPayout']);
        final payouts = (s['payouts'] as List).cast<Map>();
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(children: [
            Centered(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Earnings', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(colors: [Color(0xFF1234A8), Color(0xFF2D6BFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Available to pay out', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(money(s['available']), style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: brand),
                    onPressed: canPay ? () async {
                      try {
                        await api.post('/me/payout');
                        if (context.mounted) toast(context, 'Payout of ${money(s['available'])} sent to your bank');
                        reload();
                      } on ApiException catch (e) {
                        if (context.mounted) toast(context, e.message, error: true);
                      }
                    } : null,
                    child: Text(canPay ? 'Pay out to my bank' : 'Minimum payout ${money(s['minPayout'])}'),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 12) / 2;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  SizedBox(width: w, child: StatTile(label: 'Pending', value: money(s['pending']), icon: Icons.hourglass_bottom, color: Colors.orange, hint: '${s['disputeWindowMinutes']} min dispute window')),
                  SizedBox(width: w, child: StatTile(label: 'Paid out', value: money(s['paidOut']), icon: Icons.check_circle_outline, color: Colors.green)),
                  SizedBox(width: w, child: StatTile(label: 'This month', value: money(s['month']), icon: Icons.calendar_month)),
                  SizedBox(width: w, child: StatTile(label: 'This year', value: money(s['year']), icon: Icons.date_range)),
                ]);
              }),
              const SizedBox(height: 10),
              const Text('You keep 80% of every booking. After a booking ends, earnings are pending until the dispute window passes, then become available.', style: TextStyle(fontSize: 12, color: Colors.black45)),
              const SizedBox(height: 20),
              if (num_(s['frozen']) > 0) Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFFE3D1), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.gavel, color: Color(0xFFB34700)), const SizedBox(width: 10),
                  Expanded(child: Text('${money(s['frozen'])} is on hold while a reported problem is reviewed.', style: const TextStyle(color: Color(0xFFB34700), fontWeight: FontWeight.w600))),
                ]),
              ),
              const Text('Statements', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.download, size: 18), label: const Text('This month (CSV)'),
                  onPressed: () async {
                    try {
                      final now = DateTime.now();
                      final csv = await api.getText('/me/statement.csv', query: {'role': 'host', 'month': '${now.year}-${now.month.toString().padLeft(2, '0')}'});
                      final real = await downloadText('parkspace-earnings-${now.year}-${now.month}.csv', csv);
                      if (context.mounted) toast(context, real ? 'Statement downloaded' : 'Statement copied to clipboard');
                    } on ApiException catch (e) {
                      if (context.mounted) toast(context, e.message, error: true);
                    }
                  },
                ),
                OutlinedButton(
                  onPressed: () async {
                    final csv = await api.getText('/me/statement.csv', query: {'role': 'host'});
                    final real = await downloadText('parkspace-earnings-all.csv', csv);
                    if (context.mounted) toast(context, real ? 'Statement downloaded' : 'Statement copied to clipboard');
                  },
                  child: const Text('All time'),
                ),
              ]),
              const SizedBox(height: 20),
              const Text('Payout history', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              if (payouts.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No payouts yet', style: TextStyle(color: Colors.black54)))))
              else Card(child: Column(children: [
                for (final p in payouts)
                  ListTile(
                    leading: const CircleAvatar(backgroundColor: Color(0xFFD9F5E3), child: Icon(Icons.arrow_downward, color: Color(0xFF136C37))),
                    title: Text(money(p['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(p['sent_at'] == null ? '' : fmtFull(p['sent_at'])),
                    trailing: StatusChip('${p['status']}' == 'paid' ? 'completed' : '${p['status']}'),
                  ),
              ])),
            ])),
          ]),
        );
      },
    );
  }
}
