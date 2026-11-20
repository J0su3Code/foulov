import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../account/links.dart';
import '../account/privacy_screen.dart';
import 'auth_service.dart';

/// Connexion sans mot de passe : Google, ou code à 8 chiffres reçu par e-mail.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Step { choose, email, code, password }

class _LoginScreenState extends State<LoginScreen> {
  _Step _step = _Step.choose;
  bool _busy = false;
  String? _error;
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    // L'app a été fermée pendant qu'on cherchait le code : on reprend là où on en était.
    final pending = widget.auth.pendingEmail;
    if (pending != null) {
      _email.text = pending;
      _step = _Step.code;
    }
  }

  /// Colle un code copié depuis l'e-mail (on garde seulement les chiffres).
  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) {
      setState(() => _error = 'Aucun code à 8 chiffres dans le presse-papiers. Copie-le depuis l\'e-mail.');
      return;
    }
    _code.text = digits.substring(0, 8);
    _verifyCode();
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
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
      _error = _step == _Step.password ? 'E-mail ou mot de passe incorrect.' : _authMessage(e);
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
                    : () => setState(
                        () => _step = switch (_step) {
                          _Step.code || _Step.password => _Step.email,
                          _ => _Step.choose,
                        },
                      ),
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
                _Step.password => 'Compte de\ndémonstration',
              }, style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.1)),
              const SizedBox(height: 10),
              Text(switch (_step) {
                _Step.choose => 'Aucun mot de passe à retenir. Ensuite, tu restes connecté sur ce téléphone.',
                _Step.email => 'On t\'envoie un code à usage unique, valable 10 minutes.',
                _Step.code =>
                  'Saisis le code à 8 chiffres envoyé à ${_email.text.trim()}. Tu peux quitter l\'app pour aller le '
                      'chercher : elle t\'attendra ici.',
                _Step.password =>
                  'Réservé aux comptes de démonstration (examen de l\'app). Les autres comptes n\'ont pas '
                      'de mot de passe : ils se connectent avec un code reçu par e-mail.',
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
              if (_step == _Step.password) ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Adresse e-mail', border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Mot de passe', border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ],
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
                const SizedBox(height: 12),
                Text(
                  'En continuant, tu confirmes avoir 16 ans ou plus et tu acceptes nos conditions d\'utilisation '
                  'et notre politique de confidentialité.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.onSurfaceVariant, height: 1.35),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => openLink(context, Links.terms),
                      child: const Text('Conditions', style: TextStyle(fontSize: 12.5)),
                    ),
                    TextButton(
                      onPressed: () => openLink(context, Links.privacyPolicy),
                      child: const Text('Confidentialité', style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ],
              if (!_busy && _step == _Step.email) ...[
                FilledButton(onPressed: _emailOk ? _sendCode : null, child: const Text('Recevoir le code')),
                TextButton(
                  onPressed: () => setState(() {
                    _error = null;
                    _step = _Step.password;
                  }),
                  child: Text('Compte de démonstration', style: TextStyle(fontSize: 12.5, color: c.onSurfaceVariant)),
                ),
              ],
              if (!_busy && _step == _Step.password)
                FilledButton(
                  onPressed: _emailOk && _password.text.isNotEmpty
                      ? () => _run(() async => widget.auth.signInWithPassword(_email.text, _password.text))
                      : null,
                  child: const Text('Se connecter'),
                ),
              if (!_busy && _step == _Step.code) ...[
                FilledButton(onPressed: _code.text.length == 8 ? _verifyCode : null, child: const Text('Valider')),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('Coller le code'),
                  onPressed: _pasteCode,
                ),
                TextButton(onPressed: _sendCode, child: const Text('Renvoyer un code')),
                TextButton(
                  onPressed: () async {
                    await widget.auth.clearPending();
                    setState(() => _step = _Step.email);
                  },
                  child: const Text('Changer d\'adresse'),
                ),
              ],
              // Avant même de créer un compte : ce que nous voyons, et ce que nous ne voyons jamais.
              TextButton(
                onPressed: () => PrivacyScreen.open(context),
                child: Text(
                  'Confidentialité : ce que le serveur voit',
                  style: TextStyle(fontSize: 12.5, color: c.onSurfaceVariant),
                ),
              ),
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
