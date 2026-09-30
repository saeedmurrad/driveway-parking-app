import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../ui.dart';
import 'driver_bookings.dart';

class HostDashboard extends StatelessWidget {
  const HostDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final api = s.api;
    return Loader<(Json, List<Json>)>(
      load: () async {
        final sum = Map<String, dynamic>.from(await api.get('/me/host-summary'));
        final b = ((await api.get('/me/host-bookings')) as List).map((e) => Map<String, dynamic>.from(e)).toList();
        return (sum, b);
      },
      builder: (context, data, reload) {
        final (sum, all) = data;
        final live = all.where((b) => ['parked', 'overstay', 'confirmed'].contains(b['status'])).toList()
          ..sort((a, b) => '${a['booked_start']}'.compareTo('${b['booked_start']}'));
        final past = all.where((b) => b['status'] == 'completed').take(5).toList();
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(children: [
            Centered(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hi ${'${s.user!['name']}'.split(' ').first} 👋', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text("Here's how your spaces are doing.", style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 14),
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 12) / 2;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  SizedBox(width: w, child: StatTile(label: 'This month', value: money(sum['month']), icon: Icons.trending_up, color: Colors.teal)),
                  SizedBox(width: w, child: StatTile(label: 'Available to pay out', value: money(sum['available']), icon: Icons.account_balance_wallet_outlined)),
                  SizedBox(width: w, child: StatTile(label: 'Pending', value: money(sum['pending']), icon: Icons.hourglass_bottom, color: Colors.orange, hint: 'Released after ${sum['disputeWindowMinutes']} min dispute window')),
                  SizedBox(width: w, child: StatTile(label: 'All-time earnings', value: money(sum['allTime']), icon: Icons.savings_outlined, color: Colors.indigo)),
                ]);
              }),
              const SizedBox(height: 22),
              const Text('Active & upcoming', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              if (live.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No upcoming bookings', style: TextStyle(color: Colors.black54)))))
              else for (final b in live) Padding(padding: const EdgeInsets.only(bottom: 8), child: BookingCard(b: b, host: true, onChanged: reload)),
              const SizedBox(height: 14),
              const Text('Recently completed', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              if (past.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Nothing yet', style: TextStyle(color: Colors.black54)))))
              else for (final b in past) Padding(padding: const EdgeInsets.only(bottom: 8), child: BookingCard(b: b, host: true, onChanged: reload)),
            ])),
          ]),
        );
      },
    );
  }
}
