import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

/// Connexion sans mot de passe : Google, ou code à 8 chiffres reçu par e-mail.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Step { choose, email, code }

class _LoginScreenState extends State<LoginScreen> {
  _Step _step = _Step.choose;
  bool _busy = false;
  String? _error;
  final _email = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _error = 'La connexion Google n\'a pas abouti. Réessaie, ou utilise un code par e-mail.';
      }
    } on AuthException catch (e) {
      _error = _authMessage(e);
    } catch (_) {
      _error = 'Impossible de joindre FouLove. Vérifie ta connexion internet puis réessaie.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authMessage(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('expired') || m.contains('invalid')) {
      return 'Ce code est incorrect ou a expiré. Demande un nouveau code.';
    }
    if (m.contains('rate') || e.statusCode == '429') {
      return 'Trop de demandes. Patiente une minute avant de redemander un code.';
    }
    return 'La connexion a échoué. Réessaie dans un instant.';
  }

  bool get _emailOk => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: _step == _Step.choose
            ? null
            : IconButton(
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back),
                onPressed: _busy
                    ? null
                    : () => setState(() => _step = _step == _Step.code ? _Step.email : _Step.choose),
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.favorite_rounded, size: 44, color: c.primary),
              const SizedBox(height: 16),
              Text(switch (_step) {
                _Step.choose => 'Entrons dans\nvotre bulle.',
                _Step.email => 'Ton adresse\ne-mail',
                _Step.code => 'Vérifie\ntes e-mails',
              }, style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.1)),
              const SizedBox(height: 10),
              Text(switch (_step) {
                _Step.choose => 'Aucun mot de passe à retenir. Ensuite, tu restes connecté sur ce téléphone.',
                _Step.email => 'On t\'envoie un code à usage unique, valable 10 minutes.',
                _Step.code => 'Saisis le code à 8 chiffres envoyé à ${_email.text.trim()}.',
              }, style: t.textTheme.bodyLarge?.copyWith(color: c.onSurfaceVariant)),
              const SizedBox(height: 28),
              if (_step == _Step.email)
                TextField(
                  controller: _email,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(labelText: 'Adresse e-mail', border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _emailOk ? _sendCode() : null,
                ),
              if (_step == _Step.code)
                TextField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                  style: t.textTheme.headlineSmall?.copyWith(
                    letterSpacing: 8,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder()),
                  onChanged: (v) {
                    setState(() {});
                    if (v.length == 8) _verifyCode();
                  },
                ),
              if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: TextStyle(color: c.error))],
              const Spacer(),
              if (_busy)
                const Center(
                  child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
                ),
              if (!_busy && _step == _Step.choose) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Continuer avec Google'),
                  onPressed: () => _run(() async => widget.auth.signInWithGoogle()),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('Recevoir un code par e-mail'),
                  onPressed: () => setState(() => _step = _Step.email),
                ),
              ],
              if (!_busy && _step == _Step.email)
                FilledButton(onPressed: _emailOk ? _sendCode : null, child: const Text('Recevoir le code')),
              if (!_busy && _step == _Step.code) ...[
                FilledButton(onPressed: _code.text.length == 8 ? _verifyCode : null, child: const Text('Valider')),
                TextButton(onPressed: _sendCode, child: const Text('Renvoyer un code')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _sendCode() => _run(() async {
    await widget.auth.sendEmailCode(_email.text);
    _code.clear();
    _step = _Step.code;
  });

  void _verifyCode() => _run(() async => widget.auth.verifyEmailCode(_email.text, _code.text));
}
