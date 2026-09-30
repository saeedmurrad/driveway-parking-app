import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../ui.dart';
import 'booking_detail.dart';
import 'offers.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final r = await context.read<AppState>().api.get('/me/notifications');
      if (mounted && r['unread'] != _unread) setState(() => _unread = r['unread']);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Notifications',
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
          _poll();
        },
        icon: Badge(
          isLabelVisible: _unread > 0,
          label: Text('$_unread'),
          child: const Icon(Icons.notifications_none),
        ),
      );
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  IconData _icon(String t) => switch (t) {
        'booking_confirmed' => Icons.check_circle_outline,
        'parked' => Icons.local_parking,
        'booking_ended' => Icons.flag_outlined,
        'booking_cancelled' => Icons.cancel_outlined,
        'refund' => Icons.replay,
        'payout' => Icons.account_balance,
        'listing_approved' => Icons.verified_outlined,
        'listing_rejected' => Icons.report_outlined,
        'overstay' => Icons.timer_outlined,
        'message' => Icons.chat_bubble_outline,
        'dispute' => Icons.gavel,
        _ when t.startsWith('offer') => Icons.handshake_outlined,
        _ when t.startsWith('reminder') => Icons.alarm,
        _ => Icons.notifications_none,
      };

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Loader<List<Json>>(
        load: () async {
          final r = await api.get('/me/notifications');
          await api.post('/me/notifications/read');
          return (r['items'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
        },
        builder: (context, items, reload) => items.isEmpty
            ? const EmptyState(Icons.notifications_off_outlined, "You're all caught up", subtitle: 'Booking updates, offers and reminders appear here.')
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView(children: [
                  Centered(child: Card(child: Column(children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: items[i]['read'] == true ? const Color(0xFFEDEFF5) : const Color(0xFFDDE7FF),
                          child: Icon(_icon(items[i]['type']), color: brand, size: 20),
                        ),
                        title: Text(items[i]['title'], style: TextStyle(fontWeight: items[i]['read'] == true ? FontWeight.w500 : FontWeight.w800)),
                        subtitle: Text('${items[i]['body'] ?? ''}\n${fmtFull(items[i]['created_at'])}'),
                        isThreeLine: true,
                        onTap: () {
                          final type = items[i]['ref_type'], id = items[i]['ref_id'];
                          if (id == null) return;
                          if (type == 'booking') {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetail(bookingId: id)));
                          } else if (type == 'offer') {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => OfferThreadScreen(threadId: id)));
                          }
                        },
                      ),
                    ],
                  ]))),
                ]),
              ),
      ),
    );
  }
}
