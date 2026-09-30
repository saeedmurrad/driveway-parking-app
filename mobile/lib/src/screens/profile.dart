import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../api.dart';
import '../download.dart';
import '../ui.dart';
import 'legal.dart';
import 'verify.dart';
import 'dart:convert';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _addVehicle(BuildContext context) async {
    final plate = TextEditingController(), make = TextEditingController(), model = TextEditingController();
    String size = 'medium', connector = 'type2';
    bool isEv = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: const Text('Add a vehicle'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: plate, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Number plate')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: make, decoration: const InputDecoration(labelText: 'Make'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: model, decoration: const InputDecoration(labelText: 'Model'))),
          ]),
          const SizedBox(height: 10),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Electric vehicle'), value: isEv, onChanged: (v) => set(() => isEv = v)),
          if (isEv) DropdownButtonFormField<String>(
            initialValue: connector, decoration: const InputDecoration(labelText: 'Charging connector'),
            items: const [DropdownMenuItem(value: 'type2', child: Text('Type 2')), DropdownMenuItem(value: 'ccs', child: Text('CCS')), DropdownMenuItem(value: 'chademo', child: Text('CHAdeMO'))],
            onChanged: (v) => set(() => connector = v!),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: size, decoration: const InputDecoration(labelText: 'Size'),
            items: const [
              DropdownMenuItem(value: 'small', child: Text('Small')), DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'large', child: Text('Large')), DropdownMenuItem(value: 'van', child: Text('Van')),
            ],
            onChanged: (v) => set(() => size = v!),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      )),
    );
    if (ok != true || plate.text.trim().length < 2 || !context.mounted) return;
    final s = context.read<AppState>();
    try {
      await s.api.post('/me/vehicles', {'plate': plate.text.trim(), 'make': make.text.trim(), 'model': model.text.trim(), 'size': size, 'isEv': isEv, if (isEv) 'evConnector': connector});
      await s.loadVehicles();
    } catch (e) {
      if (context.mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final u = s.user!;
    return ListView(children: [
      Centered(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          CircleAvatar(radius: 28, backgroundColor: brand, child: Text('${u['name']}'.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text(u['email'], style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              const Chip(label: Text('Driver'), visualDensity: VisualDensity.compact),
              if (s.isHost) const Chip(label: Text('Host'), visualDensity: VisualDensity.compact),
              if (s.isAdmin) const Chip(label: Text('Admin'), visualDensity: VisualDensity.compact),
            ]),
          ])),
        ]))),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('My vehicles', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            TextButton.icon(onPressed: () => _addVehicle(context), icon: const Icon(Icons.add), label: const Text('Add')),
          ]),
          if (s.vehicles.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No vehicles yet. Add one to book a space.', style: TextStyle(color: Colors.black54))),
          for (final v in s.vehicles)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.directions_car),
              title: Text('${v['plate']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${v['make'] ?? ''} ${v['model'] ?? ''} · ${v['size']}${v['is_ev'] == true ? ' · EV (${v['ev_connector']})' : ''}'.trim()),
              trailing: s.vehicle?['id'] == v['id'] ? const Chip(label: Text('Default'), visualDensity: VisualDensity.compact) : TextButton(onPressed: () => s.selectVehicle(v['id']), child: const Text('Use')),
            ),
        ]))),
        const SizedBox(height: 12),
        if (!s.isHost)
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Have a spare driveway?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('List it in minutes and earn 80% of every booking.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.home_work_outlined), label: const Text('Become a host'),
              onPressed: () async {
                try { await s.becomeHost(); } catch (e) { if (context.mounted) toast(context, '$e', error: true); }
              },
            ),
          ]))),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Account & privacy', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ListTile(contentPadding: EdgeInsets.zero, leading: Icon(u['emailVerified'] == true && u['phoneVerified'] == true ? Icons.verified_user : Icons.verified_user_outlined, color: u['emailVerified'] == true && u['phoneVerified'] == true ? Colors.green : Colors.orange),
            title: Text(u['emailVerified'] == true && u['phoneVerified'] == true ? 'Email and phone verified' : 'Verify your account'),
            trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerifyScreen()))),
          for (final e in const [('terms', 'Terms & Conditions', Icons.description_outlined), ('privacy', 'Privacy Policy', Icons.privacy_tip_outlined), ('faq', 'Help & FAQs', Icons.help_outline)])
            ListTile(contentPadding: EdgeInsets.zero, leading: Icon(e.$3), title: Text(e.$2), trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LegalScreen(contentKey: e.$1)))),
          ListTile(
            contentPadding: EdgeInsets.zero, leading: const Icon(Icons.download_outlined), title: const Text('Download my data'), subtitle: const Text('A copy of everything we hold about you (JSON)'),
            onTap: () async {
              try {
                final data = await s.api.get('/me/export');
                final real = await downloadText('parkspace-my-data.json', const JsonEncoder.withIndent('  ').convert(data), mime: 'application/json');
                if (context.mounted) toast(context, real ? 'Your data was downloaded' : 'Your data was copied to the clipboard');
              } on ApiException catch (e) {
                if (context.mounted) toast(context, e.message, error: true);
              }
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline, color: Colors.red.shade700), title: Text('Delete my account', style: TextStyle(color: Colors.red.shade700)),
            subtitle: const Text('Financial records are kept as the law requires; everything else is anonymised'),
            onTap: () async {
              final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                title: const Text('Delete your account?'),
                content: const Text('This cannot be undone. Your listings are removed and your personal details are anonymised. You need to finish or cancel upcoming bookings first.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep my account')),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700), onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                ],
              ));
              if (ok != true) return;
              try {
                await s.api.delete('/me');
                await s.logout();
              } on ApiException catch (e) {
                if (context.mounted) toast(context, e.message, error: true);
              }
            },
          ),
        ]))),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: s.logout, icon: const Icon(Icons.logout), label: const Text('Sign out')),
      ])),
    ]);
  }
}
