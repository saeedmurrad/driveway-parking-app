import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../ui.dart';
import 'booking_detail.dart';

/// Shared by driver (My Bookings) and host (bookings on my spaces).
class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.b, required this.host, required this.onChanged});
  final Json b;
  final bool host;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final status = b['status'] as String;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetail(bookingId: b['id'])));
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(b['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              StatusChip(status),
            ]),
            const SizedBox(height: 6),
            Text(fmtRange(b['booked_start'], b['booked_end']), style: const TextStyle(color: Colors.black87)),
            const SizedBox(height: 4),
            Text(
              host ? '${b['other_name']}${b['plate'] != null ? ' · ${b['plate']}' : ''}' : (b['address'] ?? 'Address shared after payment'),
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            if (status == 'completed' && b['actual_parked_at'] != null) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Parked ${fmtTime(dt(b['actual_parked_at']))} · left ${b['actual_ended_at'] == null ? '—' : fmtTime(dt(b['actual_ended_at']))}', style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${b['reference']}', style: const TextStyle(fontSize: 12, color: Colors.black45)),
              Text(host ? '+${money(b['host_earnings'])}' : money(b['total_amount']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class BookingTabs extends StatelessWidget {
  const BookingTabs({super.key, required this.host, this.header});
  final bool host;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<Json>>(
      load: () async => ((await api.get(host ? '/me/host-bookings' : '/me/bookings')) as List).map((e) => Map<String, dynamic>.from(e)).toList(),
      builder: (context, all, reload) {
        List<Json> of(List<String> s) => all.where((b) => s.contains(b['status'])).toList();
        final tabs = <(String, List<Json>)>[
          ('Upcoming', of(['confirmed'])..sort((a, b) => '${a['booked_start']}'.compareTo('${b['booked_start']}'))),
          ('Active', of(['parked', 'overstay'])),
          ('Past', of(['completed'])),
          ('Cancelled', of(['cancelled'])),
        ];
        return DefaultTabController(
          length: tabs.length,
          child: Column(children: [
            Container(color: Colors.white, child: TabBar(tabs: [for (final t in tabs) Tab(text: '${t.$1} (${t.$2.length})')])),
            Expanded(child: TabBarView(children: [
              for (final t in tabs)
                RefreshIndicator(
                  onRefresh: reload,
                  child: t.$2.isEmpty
                      ? ListView(children: [SizedBox(height: 320, child: EmptyState(Icons.inbox_outlined, 'Nothing here yet', subtitle: host ? 'Bookings on your spaces will show up here.' : 'Find a space on the Explore tab to get started.'))])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: t.$2.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: BookingCard(b: t.$2[i], host: host, onChanged: reload))),
                        ),
                ),
            ])),
          ]),
        );
      },
    );
  }
}

class DriverBookings extends StatelessWidget {
  const DriverBookings({super.key});

  @override
  Widget build(BuildContext context) => const BookingTabs(host: false);
}
