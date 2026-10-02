import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

export 'api.dart' show Json;

const brand = Color(0xFF2350F0);
const brandDark = Color(0xFF0F2FA8);
const heroGradient = LinearGradient(colors: [Color(0xFF0F2FA8), Color(0xFF2F6BFF)], begin: Alignment.topLeft, end: Alignment.bottomRight);

double num_(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String money(dynamic v) {
  final n = num_(v);
  return '${n < 0 ? '-' : ''}£${n.abs().toStringAsFixed(2)}';
}
DateTime dt(dynamic v) => DateTime.parse('$v').toLocal();
String fmtDay(DateTime d) => DateFormat('EEE d MMM').format(d);
String fmtTime(DateTime d) => DateFormat('HH:mm').format(d);
String fmtFull(dynamic v) => DateFormat('EEE d MMM, HH:mm').format(dt(v));
String fmtRange(dynamic a, dynamic b) {
  final s = dt(a), e = dt(b);
  final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
  return sameDay ? '${fmtDay(s)} · ${fmtTime(s)}–${fmtTime(e)}' : '${fmtDay(s)} ${fmtTime(s)} → ${fmtDay(e)} ${fmtTime(e)}';
}

void toast(BuildContext c, String msg, {bool error = false}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
}

const featureIcons = <String, (IconData, String)>{
  'covered': (Icons.roofing, 'Covered'),
  'lit': (Icons.lightbulb_outline, 'Lit at night'),
  'gated': (Icons.fence, 'Gated'),
  'cctv': (Icons.videocam_outlined, 'CCTV'),
  'ev_charging': (Icons.ev_station, 'EV charging'),
  'level_access': (Icons.accessible, 'Level access'),
};

const spaceIcons = <String, IconData>{
  'driveway': Icons.home_outlined,
  'garage': Icons.garage_outlined,
  'bay': Icons.local_parking,
  'forecourt': Icons.apartment,
};

const policyText = <String, String>{
  'flexible': 'Flexible: full refund if cancelled 1 hour or more before start.',
  'moderate': 'Moderate: full refund 24h+ before start, 50% from 1–24h before.',
  'strict': 'Strict: full refund 48h+ before start, 50% from 24–48h before.',
};

({Color bg, Color fg, String label}) statusStyle(String s) => switch (s) {
      'requested' => (bg: const Color(0xFFFFF0C9), fg: const Color(0xFF8A5B00), label: 'Awaiting host'),
      'confirmed' => (bg: const Color(0xFFDCEBFF), fg: const Color(0xFF1148B8), label: 'Confirmed'),
      'parked' => (bg: const Color(0xFFD9F5E3), fg: const Color(0xFF136C37), label: 'Parked'),
      'overstay' => (bg: const Color(0xFFFFE3D1), fg: const Color(0xFFB34700), label: 'Overstay'),
      'completed' => (bg: const Color(0xFFE8EAF0), fg: const Color(0xFF414755), label: 'Completed'),
      'cancelled' => (bg: const Color(0xFFFFDDDD), fg: const Color(0xFFA11B1B), label: 'Cancelled'),
      'live' => (bg: const Color(0xFFD9F5E3), fg: const Color(0xFF136C37), label: 'Live'),
      'paused' => (bg: const Color(0xFFFFF0C9), fg: const Color(0xFF8A5B00), label: 'Paused'),
      'pending_approval' => (bg: const Color(0xFFFFF0C9), fg: const Color(0xFF8A5B00), label: 'Pending approval'),
      'rejected' => (bg: const Color(0xFFFFDDDD), fg: const Color(0xFFA11B1B), label: 'Rejected'),
      _ => (bg: const Color(0xFFE8EAF0), fg: const Color(0xFF414755), label: s),
    };

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final s = statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(s.label, style: TextStyle(color: s.fg, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Centres content and caps its width so pages look right on wide browser windows.
class Centered extends StatelessWidget {
  const Centered({super.key, required this.child, this.maxWidth = 760, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(padding: padding, child: child),
        ),
      );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon, this.color, this.hint});
  final String label, value;
  final String? hint;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? brand;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 18, color: c),
            ),
            if (icon != null) const SizedBox(width: 8),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54))),
          ]),
          const SizedBox(height: 10),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint!, style: const TextStyle(fontSize: 11, color: Colors.black45))),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.title, {super.key, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Colors.black26),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            ),
          ]),
        ),
      );
}

/// Loads data once, shows spinner / error, supports pull-to-refresh via [reload].
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function() reload) builder;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _f = widget.load();

  Future<void> _reload() async {
    setState(() => _f = widget.load());
    await _f.catchError((_) => null as T);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.black38),
                  const SizedBox(height: 8),
                  Text('${snap.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.tonal(onPressed: _reload, child: const Text('Try again')),
                ]),
              ),
            );
          }
          return builder(context, snap.data as T, _reload);
        },
      );

  Widget builder(BuildContext c, T data, Future<void> Function() r) => widget.builder(c, data, r);
}

class Stars extends StatelessWidget {
  const Stars(this.rating, {super.key, this.size = 16});
  final dynamic rating;
  final double size;

  @override
  Widget build(BuildContext context) => rating == null
      ? Text('New', style: TextStyle(fontSize: size - 3, color: Colors.black54))
      : Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.star_rounded, size: size, color: const Color(0xFFF5A623)),
          const SizedBox(width: 2),
          Text(num_(rating).toStringAsFixed(1), style: TextStyle(fontSize: size - 2, fontWeight: FontWeight.w600)),
        ]);
}

/// Gradient banner with a big headline number (earnings, spending, etc.).
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key, required this.eyebrow, required this.title, this.subtitle, this.trailing, this.children = const []});
  final String eyebrow, title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        decoration: BoxDecoration(
          gradient: heroGradient, borderRadius: BorderRadius.circular(26),
          boxShadow: const [BoxShadow(color: Color(0x332350F0), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: Stack(children: [
          Positioned(right: -30, top: -40, child: Container(width: 140, height: 140, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.08)))),
          Positioned(right: 40, bottom: -50, child: Container(width: 100, height: 100, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)))),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(eyebrow, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13))),
              ?trailing,
            ]),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, height: 1.1)),
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 13))),
            ...children,
          ]),
        ]),
      );
}
