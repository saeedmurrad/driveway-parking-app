// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../ui.dart';

/// Email and phone verification (spec s3). In demo mode the API returns the codes so they can be shown here.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, this.initialEmailCode});
  final String? initialEmailCode;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _emailCode = TextEditingController();
  final _phone = TextEditingController();
  final _phoneCode = TextEditingController();
  String? _demoEmail, _demoPhone;
  bool _busy = false, _codeSent = false;

  @override
  void initState() {
    super.initState();
    _demoEmail = widget.initialEmailCode;
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final u = s.user!;
    final emailOk = u['emailVerified'] == true, phoneOk = u['phoneVerified'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your account')),
      body: ListView(children: [
        Centered(maxWidth: 520, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('To keep everyone safe, please verify your email and mobile number before booking or listing a space.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(emailOk ? Icons.check_circle : Icons.mail_outline, color: emailOk ? Colors.green : brand), const SizedBox(width: 8), Text('1. Email', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))]),
            const SizedBox(height: 6),
            if (emailOk) Text('${u['email']} is verified.', style: const TextStyle(color: Colors.green))
            else ...[
              Text('We emailed a 6-digit code to ${u['email']}.'),
              if (_demoEmail != null) _demoHint(_demoEmail!),
              const SizedBox(height: 10),
              TextField(controller: _emailCode, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: '6-digit code', counterText: '')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: FilledButton(onPressed: _busy ? null : () => _run(() async {
                  await s.api.post('/me/verify-email', {'code': _emailCode.text.trim()});
                  await s.refreshUser();
                  if (context.mounted) toast(context, 'Email verified');
                }), child: const Text('Verify email'))),
                const SizedBox(width: 8),
                TextButton(onPressed: _busy ? null : () => _run(() async {
                  final r = await s.api.post('/me/resend-email');
                  setState(() => _demoEmail = r['devCode']);
                  if (context.mounted) toast(context, 'New code sent');
                }), child: const Text('Resend')),
              ]),
            ],
          ]))),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(phoneOk ? Icons.check_circle : Icons.sms_outlined, color: phoneOk ? Colors.green : brand), const SizedBox(width: 8), Text('2. Mobile number', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))]),
            const SizedBox(height: 6),
            if (phoneOk) Text('${u['phone']} is verified.', style: const TextStyle(color: Colors.green))
            else ...[
              TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number', hintText: '+44 7700 900123')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _busy ? null : () => _run(() async {
                final r = await s.api.post('/me/phone', {'phone': _phone.text.trim()});
                setState(() { _codeSent = true; _demoPhone = r['devCode']; });
              }), child: Text(_codeSent ? 'Send a new code' : 'Text me a code')),
              if (_codeSent) ...[
                if (_demoPhone != null) _demoHint(_demoPhone!),
                const SizedBox(height: 10),
                TextField(controller: _phoneCode, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'SMS code', counterText: '')),
                const SizedBox(height: 8),
                FilledButton(onPressed: _busy ? null : () => _run(() async {
                  await s.api.post('/me/verify-phone', {'code': _phoneCode.text.trim()});
                  await s.refreshUser();
                  if (context.mounted) toast(context, 'Phone verified');
                }), child: const Text('Verify phone')),
              ],
            ],
          ]))),
          if (emailOk && phoneOk) ...[
            const SizedBox(height: 16),
            FilledButton.icon(icon: const Icon(Icons.check), label: const Text("You're all set"), onPressed: () => Navigator.pop(context)),
          ],
        ])),
      ]),
    );
  }

  Widget _demoHint(String code) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.science_outlined, size: 18, color: Color(0xFF8A5B00)), const SizedBox(width: 8),
          Expanded(child: Text('Demo mode: no real email/SMS is sent. Your code is $code', style: const TextStyle(color: Color(0xFF8A5B00), fontWeight: FontWeight.w600))),
          TextButton(onPressed: () => (code == _demoEmail ? _emailCode : _phoneCode).text = code, child: const Text('Fill')),
        ]),
      );
}

/// Banner shown on the main screens until both checks are done.
class VerifyBanner extends StatelessWidget {
  const VerifyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final u = s.user;
    if (u == null || (u['emailVerified'] == true && u['phoneVerified'] == true)) return const SizedBox();
    return Material(
      color: const Color(0xFFFFF0C9),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerifyScreen())),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(Icons.verified_user_outlined, color: Color(0xFF8A5B00)), SizedBox(width: 10),
            Expanded(child: Text('Verify your email and phone to book or list a space', style: TextStyle(color: Color(0xFF8A5B00), fontWeight: FontWeight.w700))),
            Icon(Icons.chevron_right, color: Color(0xFF8A5B00)),
          ]),
        ),
      ),
    );
  }
}
