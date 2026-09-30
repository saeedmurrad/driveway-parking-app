import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../ui.dart';

/// Admin-editable Terms, Privacy Policy and FAQs (served from the `content` table).
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.contentKey});
  final String contentKey;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Scaffold(
      appBar: AppBar(title: const Text('Info')),
      body: Loader<Json>(
        load: () async => Map<String, dynamic>.from(await api.get('/content/$contentKey')),
        builder: (context, c, _) => ListView(children: [
          Centered(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['title'], style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text('Version ${c['version']}', style: const TextStyle(color: Colors.black45, fontSize: 12)),
            const SizedBox(height: 14),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(c['body'], style: const TextStyle(height: 1.5)))),
          ])),
        ]),
      ),
    );
  }
}
