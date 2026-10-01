import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../api.dart';
import '../download.dart';
import '../ui.dart';
import 'driver_bookings.dart';

class SpendingScreen extends StatelessWidget {
  const SpendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<(Json, List<Json>)>(
      load: () async {
        final s = Map<String, dynamic>.from(await api.get('/me/driver-summary'));
        final b = ((await api.get('/me/bookings')) as List).map((e) => Map<String, dynamic>.from(e)).toList();
        return (s, b);
      },
      builder: (context, data, reload) {
        final (s, bookings) = data;
        final paid = bookings.where((b) => b['status'] != 'cancelled').toList();
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(children: [
            Centered(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              HeroHeader(
                eyebrow: 'Spent this month',
                title: money(s['month']),
                subtitle: '${money(s['allTime'])} all time · ${s['bookings']} bookings',
                trailing: const Icon(Icons.receipt_long_outlined, color: Colors.white70),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 12) / 2;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  SizedBox(width: w, child: StatTile(label: 'This month', value: money(s['month']), icon: Icons.calendar_month)),
                  SizedBox(width: w, child: StatTile(label: 'This year', value: money(s['year']), icon: Icons.date_range)),
                  SizedBox(width: w, child: StatTile(label: 'All time', value: money(s['allTime']), icon: Icons.account_balance_wallet_outlined)),
                  SizedBox(width: w, child: StatTile(label: 'Bookings', value: '${s['bookings']}', icon: Icons.local_parking, color: Colors.teal)),
                ]);
              }),
              const SizedBox(height: 20),
              Row(children: [
                const Expanded(child: Text('Receipts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                OutlinedButton.icon(
                  icon: const Icon(Icons.download, size: 18), label: const Text('Statement (CSV)'),
                  onPressed: () async {
                    try {
                      final csv = await api.getText('/me/statement.csv', query: {'role': 'driver'});
                      final real = await downloadText('parkspace-spending.csv', csv);
                      if (context.mounted) toast(context, real ? 'Statement downloaded' : 'Statement copied to clipboard');
                    } on ApiException catch (e) {
                      if (context.mounted) toast(context, e.message, error: true);
                    }
                  },
                ),
              ]),
              const SizedBox(height: 8),
              if (paid.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No payments yet')))
              else for (final b in paid) Padding(padding: const EdgeInsets.only(bottom: 8), child: BookingCard(b: b, host: false, onChanged: reload)),
            ])),
          ]),
        );
      },
    );
  }
}
