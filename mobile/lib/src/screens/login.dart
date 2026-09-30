import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false, _host = false, _busy = false;

  Future<void> _submit([String? email]) async {
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      if (email != null) {
        await s.login(email, 'demo1234');
      } else if (_register) {
        await s.register(_name.text.trim(), _email.text.trim(), _pass.text, _host);
      } else {
        await s.login(_email.text.trim(), _pass.text);
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
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
                      if (_register)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero, value: _host, onChanged: (v) => setState(() => _host = v ?? false),
                          title: const Text('I also want to rent out my driveway'),
                        ),
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

  Widget _demo(IconData icon, String label, String email) => ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onPressed: _busy ? null : () => _submit(email),
      );
}
