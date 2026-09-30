// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../../main.dart' show navigatorKey;
import '../api.dart';
import '../ui.dart';
import 'legal.dart';
import 'verify.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false, _host = false, _busy = false, _terms = false;

  Future<void> _submit([String? email]) async {
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      if (email != null) {
        await s.login(email, 'demo1234');
      } else if (_register) {
        if (!_terms) throw ApiException('Please accept the Terms & Conditions and Privacy Policy', 0);
        final code = await s.register(_name.text.trim(), _email.text.trim(), _pass.text, _host);
        // Straight on to verification; the banner keeps nagging until it is done.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final nav = navigatorKey.currentState;
          nav?.push(MaterialPageRoute(builder: (_) => VerifyScreen(initialEmailCode: code)));
        });
      } else {
        await s.login(_email.text.trim(), _pass.text);
      }
    } catch (e) {
      if (context.mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF1234A8), Color(0xFF2D6BFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: const Center(child: Text('P', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: brand))),
                ),
                const SizedBox(height: 14),
                const Text('ParkSpace', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Rent a driveway. Park in minutes.', style: TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(_register ? 'Create your account' : 'Welcome back', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      if (_register) ...[
                        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
                        const SizedBox(height: 12),
                      ],
                      TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
                      const SizedBox(height: 12),
                      TextField(controller: _pass, obscureText: true, onSubmitted: (_) => _submit(), decoration: const InputDecoration(labelText: 'Password')),
                      if (_register) ...[
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero, value: _host, onChanged: (v) => setState(() => _host = v ?? false),
                          title: const Text('I also want to rent out my driveway'),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero, value: _terms, onChanged: (v) => setState(() => _terms = v ?? false),
                          title: Wrap(children: [
                            const Text('I accept the '),
                            InkWell(onTap: () => _legal('terms'), child: const Text('Terms & Conditions', style: TextStyle(color: brand, decoration: TextDecoration.underline))),
                            const Text(' and '),
                            InkWell(onTap: () => _legal('privacy'), child: const Text('Privacy Policy', style: TextStyle(color: brand, decoration: TextDecoration.underline))),
                          ]),
                        ),
                      ],
                      if (!_register) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _forgot, child: const Text('Forgot password?'))),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : () => _submit(),
                        child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_register ? 'Create account' : 'Sign in'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _register = !_register),
                        child: Text(_register ? 'Already have an account? Sign in' : 'New here? Create an account'),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Try a demo account', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _demo(Icons.directions_car, 'Driver', 'driver@demo.parkspace.test'),
                        _demo(Icons.home_work_outlined, 'Host', 'host@demo.parkspace.test'),
                        _demo(Icons.admin_panel_settings_outlined, 'Admin', 'admin@demo.parkspace.test'),
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _legal(String key) => navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => _PublicLegal(contentKey: key)));

  Future<void> _forgot() async {
    final email = TextEditingController(text: _email.text);
    final code = TextEditingController(), pass = TextEditingController();
    String? demo;
    bool sent = false, busy = false;
    final api = context.read<AppState>().api;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: const Text('Reset your password'),
        content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: email, enabled: !sent, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
          if (sent) ...[
            const SizedBox(height: 10),
            const Align(alignment: Alignment.centerLeft, child: Text('If that email has an account, we have sent a 6-digit code.')),
            if (demo != null) Container(
              margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(10), width: double.infinity,
              decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(10)),
              child: Text('Demo mode: your code is $demo', style: const TextStyle(color: Color(0xFF8A5B00), fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
            TextField(controller: code, maxLength: 6, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6-digit code', counterText: '')),
            const SizedBox(height: 10),
            TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'New password (6+ characters)')),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
          FilledButton(
            onPressed: busy ? null : () async {
              set(() => busy = true);
              try {
                if (!sent) {
                  final r = await api.post('/auth/forgot', {'email': email.text.trim()});
                  set(() { sent = true; demo = r['devCode']; });
                } else {
                  await api.post('/auth/reset', {'email': email.text.trim(), 'code': code.text.trim(), 'password': pass.text});
                  if (c.mounted) Navigator.pop(c);
                  if (context.mounted) toast(context, 'Password changed. You can sign in now.');
                }
              } on ApiException catch (e) {
                if (c.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
              } finally {
                set(() => busy = false);
              }
            },
            child: Text(sent ? 'Change password' : 'Send code'),
          ),
        ],
      )),
    );
  }

  Widget _demo(IconData icon, String label, String email) => ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onPressed: _busy ? null : () => _submit(email),
      );
}

/// Terms/Privacy are readable before logging in, so they are fetched without a token.
class _PublicLegal extends StatelessWidget {
  const _PublicLegal({required this.contentKey});
  final String contentKey;

  @override
  Widget build(BuildContext context) => LegalScreen(contentKey: contentKey);
}
