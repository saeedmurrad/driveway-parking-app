import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../ui.dart';

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key, required this.listingId, required this.title});
  final String listingId, title;

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

// Monday first, but the API uses 0 = Sunday.
const _days = [(1, 'Monday'), (2, 'Tuesday'), (3, 'Wednesday'), (4, 'Thursday'), (5, 'Friday'), (6, 'Saturday'), (0, 'Sunday')];

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  bool _loading = true, _always = true, _busy = false;
  final Map<int, (TimeOfDay, TimeOfDay)?> _week = {for (final d in _days) d.$1: null};
  List<Json> _blocks = [];

  Api get _api => context.read<AppState>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  TimeOfDay _t(String s) => s == '24:00' ? const TimeOfDay(hour: 23, minute: 59) : TimeOfDay(hour: int.parse(s.substring(0, 2)), minute: int.parse(s.substring(3)));
  String _s(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    try {
      final r = await _api.get('/listings/${widget.listingId}/availability');
      final rules = (r['rules'] as List).cast<Map>();
      setState(() {
        _always = r['always'] == true;
        for (final d in _days) {
          _week[d.$1] = null;
        }
        for (final x in rules) {
          _week[x['day_of_week']] ??= (_t(x['start']), _t(x['end']));
        }
        if (_always) {
          for (final d in _days) {
            _week[d.$1] = (const TimeOfDay(hour: 8, minute: 0), const TimeOfDay(hour: 18, minute: 0));
          }
        }
        _blocks = (r['blocks'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        toast(context, '$e', error: true);
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _api.put('/listings/${widget.listingId}/availability', {
        'always': _always,
        'rules': [
          if (!_always)
            for (final d in _days)
              if (_week[d.$1] != null) {'dayOfWeek': d.$1, 'start': _s(_week[d.$1]!.$1), 'end': _s(_week[d.$1]!.$2) == '23:59' ? '24:00' : _s(_week[d.$1]!.$2)},
        ],
      });
      if (mounted) toast(context, 'Availability saved');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(int dow, bool start) async {
    final cur = _week[dow]!;
    final t = await showTimePicker(context: context, initialTime: start ? cur.$1 : cur.$2);
    if (t != null) setState(() => _week[dow] = start ? (t, cur.$2) : (cur.$1, t));
  }

  Future<void> _addBlock() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (range == null || !mounted) return;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Block these dates?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${fmtDay(range.start)} – ${fmtDay(range.end)} (whole days)'),
          const SizedBox(height: 10),
          TextField(controller: reason, decoration: const InputDecoration(hintText: 'Reason (optional), e.g. I need my drive')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Block')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.post('/listings/${widget.listingId}/blocks', {
        'start': DateTime(range.start.year, range.start.month, range.start.day).toUtc().toIso8601String(),
        'end': DateTime(range.end.year, range.end.month, range.end.day, 23, 59).toUtc().toIso8601String(),
        'reason': reason.text.trim(),
      });
      _load();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Availability')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(children: [
                Centered(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(widget.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('Times are UK local time. Drivers can only book inside your opening hours, and a booked slot is removed automatically.', style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 12),
                  Card(child: SwitchListTile(
                    title: const Text('Always available (24/7)'),
                    value: _always,
                    onChanged: (v) => setState(() => _always = v),
                  )),
                  if (!_always) ...[
                    const SizedBox(height: 12),
                    Card(child: Column(children: [
                      for (final d in _days)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Column(children: [
                            Row(children: [
                              Switch(
                                value: _week[d.$1] != null,
                                onChanged: (v) => setState(() => _week[d.$1] = v ? (const TimeOfDay(hour: 8, minute: 0), const TimeOfDay(hour: 18, minute: 0)) : null),
                              ),
                              const SizedBox(width: 8),
                              Text(d.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                              const Spacer(),
                              if (_week[d.$1] == null) const Text('Closed', style: TextStyle(color: Colors.black45)),
                            ]),
                            if (_week[d.$1] != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 60, top: 2),
                                child: Row(children: [
                                  Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)), onPressed: () => _pick(d.$1, true), child: Text(_week[d.$1]!.$1.format(context)))),
                                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('to')),
                                  Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)), onPressed: () => _pick(d.$1, false), child: Text(_week[d.$1]!.$2.format(context)))),
                                ]),
                              ),
                          ]),
                        ),
                    ])),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(onPressed: _busy ? null : _save, child: const Text('Save weekly hours')),
                  const SizedBox(height: 26),
                  Row(children: [
                    const Expanded(child: Text('Blocked dates', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                    TextButton.icon(onPressed: _addBlock, icon: const Icon(Icons.add), label: const Text('Block dates')),
                  ]),
                  if (_blocks.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No blocked dates', style: TextStyle(color: Colors.black54)))))
                  else Card(child: Column(children: [
                    for (final b in _blocks)
                      ListTile(
                        leading: const Icon(Icons.block, color: Colors.redAccent),
                        title: Text('${fmtDay(dt(b['start_datetime']))} – ${fmtDay(dt(b['end_datetime']))}'),
                        subtitle: Text(b['reason'] ?? 'Blocked'),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
                          await _api.delete('/listings/${widget.listingId}/blocks/${b['id']}');
                          _load();
                        }),
                      ),
                  ])),
                ])),
              ]),
      );
}
