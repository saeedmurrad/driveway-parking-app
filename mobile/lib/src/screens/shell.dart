import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../ui.dart';
import 'admin.dart';
import 'driver_bookings.dart';
import 'explore.dart';
import 'host_dashboard.dart';
import 'host_earnings.dart';
import 'host_listings.dart';
import 'notifications.dart';
import 'profile.dart';
import 'spending.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  Mode? _lastMode;

  List<(IconData, IconData, String, Widget)> _tabs(Mode m) => switch (m) {
        Mode.driver => [
            (Icons.map_outlined, Icons.map, 'Explore', const ExploreScreen()),
            (Icons.confirmation_number_outlined, Icons.confirmation_number, 'Bookings', const DriverBookings()),
            (Icons.receipt_long_outlined, Icons.receipt_long, 'Spending', const SpendingScreen()),
            (Icons.person_outline, Icons.person, 'Profile', const ProfileScreen()),
          ],
        Mode.host => [
            (Icons.dashboard_outlined, Icons.dashboard, 'Dashboard', const HostDashboard()),
            (Icons.home_work_outlined, Icons.home_work, 'My spaces', const HostListings()),
            (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Earnings', const HostEarnings()),
            (Icons.person_outline, Icons.person, 'Profile', const ProfileScreen()),
          ],
        Mode.admin => [
            (Icons.insights_outlined, Icons.insights, 'Overview', const AdminOverview()),
            (Icons.fact_check_outlined, Icons.fact_check, 'Listings', const AdminListings()),
            (Icons.list_alt_outlined, Icons.list_alt, 'Bookings', const AdminBookings()),
            (Icons.tune, Icons.tune, 'Settings', const AdminSettings()),
          ],
      };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (_lastMode != s.mode) {
      _lastMode = s.mode;
      _tab = 0;
    }
    final tabs = _tabs(s.mode);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = IndexedStack(index: _tab, children: [
      for (final t in tabs) KeyedSubtree(key: ValueKey('${s.mode}-${t.$3}'), child: t.$4),
    ]);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(9)),
            child: const Center(child: Text('P', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20))),
          ),
          const SizedBox(width: 10),
          const Text('ParkSpace', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [
          const NotificationBell(),
          _ModeSwitcher(state: s),
          const SizedBox(width: 12),
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                backgroundColor: Colors.white,
                selectedIndex: _tab,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [for (final t in tabs) NavigationRailDestination(icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: Text(t.$3))],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: t.$3)],
            ),
    );
  }
}

class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final modes = [Mode.driver, if (state.isHost) Mode.host, if (state.isAdmin) Mode.admin];
    if (modes.length == 1) {
      return Chip(avatar: const Icon(Icons.directions_car, size: 16), label: Text(state.user?['name'] ?? ''));
    }
    const icons = {Mode.driver: Icons.directions_car, Mode.host: Icons.home_work_outlined, Mode.admin: Icons.admin_panel_settings_outlined};
    const labels = {Mode.driver: 'Driver', Mode.host: 'Host', Mode.admin: 'Admin'};
    return SegmentedButton<Mode>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [for (final m in modes) ButtonSegment(value: m, icon: Icon(icons[m], size: 16), label: Text(labels[m]!))],
      selected: {state.mode},
      onSelectionChanged: (v) => state.setMode(v.first),
    );
  }
}
