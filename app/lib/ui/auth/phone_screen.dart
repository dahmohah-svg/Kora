import 'package:flutter/material.dart';

import '../../data/phone.dart';
import '../api_scope.dart';
import '../labels.dart';

/// Sign in with phone number and SMS code. On success the AuthGate moves on
/// by itself.
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _sentTo;
  String? _phoneError;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = normalizeEgyptianMobile(_phone.text);
    if (phone == null) {
      setState(() => _phoneError = context.l10n.invalidPhone);
      return;
    }
    setState(() {
      _phoneError = null;
      _busy = true;
    });
    final ok = await runAction(context, () => ApiScope.of(context).sendOtp(phone));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _sentTo = phone;
    });
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    await runAction(context, () => ApiScope.of(context).verifyOtp(_sentTo!, _code.text.trim()));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 48),
            Text(l.appTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 48),
            if (_sentTo == null) ...[
              Text(l.phoneTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                key: const Key('phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: l.phoneHint,
                  errorText: _phoneError,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.phone_android),
                ),
                onSubmitted: (_) => _sendCode(),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : _sendCode, child: Text(l.sendCode)),
            ] else ...[
              Text(l.codeTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(l.codeSentTo(_sentTo!)),
              const SizedBox(height: 16),
              TextField(
                key: const Key('code'),
                controller: _code,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                maxLength: 6,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _busy ? null : _verify, child: Text(l.verify)),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _sentTo = null),
                child: Text(l.back),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
