import 'package:flutter/material.dart';

import '../../i18n/app_strings.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlock});

  final Future<bool> Function(String password) onUnlock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.text('App is locked'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(s.text('Enter password to unlock this workspace.')),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  enabled: !_isBusy,
                  decoration: InputDecoration(labelText: s.text('Password')),
                  onSubmitted: (_) => _unlock(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isBusy ? null : _unlock,
                  child:
                      _isBusy
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Text(s.text('Unlock')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _unlock() async {
    setState(() {
      _error = null;
      _isBusy = true;
    });
    final ok = await widget.onUnlock(_passwordController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _isBusy = false;
      _error = ok ? null : context.strings.text('Invalid password.');
      if (ok) {
        _passwordController.clear();
      }
    });
  }
}
