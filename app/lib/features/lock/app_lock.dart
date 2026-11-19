import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../src/rust/api/lock.dart';
import '../../theme/foulov_theme.dart';
import '../../ui/love.dart';

/// Verrouillage de l'app (docs/SECURITY.md §7), à l'ouverture et après une minute en arrière-plan.
///
/// Deux façons de l'ouvrir, au choix :
/// - **le code FouLove** (6 chiffres), propre à l'app : marche même si le téléphone n'a aucun verrouillage.
///   Seule son empreinte Argon2id est gardée, dans le coffre du système. Après 5 erreurs, il faut attendre
///   (30 s, puis 1 min, 2 min… jusqu'à 1 h), même si l'app est fermée et rouverte ;
/// - **l'empreinte, le visage ou le code du téléphone**, seuls ou en raccourci du code FouLove.
///
/// C'est un verrou d'accès à l'interface, comme celui de Signal. La clé de la base locale reste protégée par le
/// Keystore sans exiger d'authentification : sinon, retirer le verrouillage d'écran du téléphone détruirait la clé,
/// et tout l'historique avec.
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock._();
  static final instance = AppLock._();

  static const _pref = 'foulov.app_lock'; // empreinte / visage / code du téléphone : 'on' ou 'off'
  static const _pinKey = 'foulov.pin';
  static const _failKey = 'foulov.pin_failures';
  static const _untilKey = 'foulov.pin_until';
  static const _grace = Duration(minutes: 1);
  static const _store = FlutterSecureStorage();
  static const _native = MethodChannel('foulove/notifications');
  final _auth = LocalAuthentication();

  /// Le téléphone a un verrouillage d'écran (empreinte, visage ou code).
  bool supported = false;

  /// L'empreinte, le visage ou le code du téléphone ouvrent l'app.
  bool biometrics = false;
  String? _pin;
  bool locked = false;
  int failures = 0;
  DateTime? waitUntil;
  bool _authenticating = false;
  DateTime? _leftAt;

  /// « Code oublié » : déconnexion (fournie par l'app), puis le code est retiré.
  Future<void> Function()? onForgot;

  bool get hasPin => _pin != null;
  bool get enabled => hasPin || biometrics;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      supported = await _auth.isDeviceSupported();
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] verrouillage indisponible : $e');
      supported = false;
    }
    if (kDebugMode) debugPrint('[FOULOVE] verrouillage : appareil compatible = $supported');
    _pin = await _store.read(key: _pinKey);
    failures = int.tryParse(await _store.read(key: _failKey) ?? '') ?? 0;
    waitUntil = DateTime.tryParse(await _store.read(key: _untilKey) ?? '');
    // Empreinte activée par défaut dès que le téléphone a un verrouillage d'écran.
    biometrics = supported && (await _store.read(key: _pref)) != 'off';
    locked = enabled;
    await _hideInRecents(enabled);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_authenticating) return; // la boîte de dialogue biométrique met l'app en pause
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (enabled && left != null && DateTime.now().difference(left) >= _grace && !locked) {
        locked = true;
        notifyListeners();
      }
    }
  }

  Future<bool> _authenticate(String reason) async {
    if (_authenticating || !supported) return false;
    _authenticating = true;
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } on LocalAuthException catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] verrouillage : $e');
      return false;
    } finally {
      _authenticating = false;
      _leftAt = null;
    }
  }

  /// Confirme une action sensible : l'empreinte si elle est active, sinon le code FouLove (`askPin` affiche la
  /// saisie et renvoie vrai si le code est juste). Sans aucun verrou, l'action est permise.
  Future<bool> confirm(String reason, {Future<bool> Function()? askPin}) async {
    if (biometrics && await _authenticate(reason)) return true;
    if (hasPin && askPin != null) return askPin();
    return !enabled;
  }

  Future<void> unlockWithBiometrics() async {
    if (!locked || !biometrics) return;
    if (await _authenticate('Déverrouille FouLove')) _unlocked();
  }

  void _unlocked() {
    locked = false;
    notifyListeners();
  }

  // ------------------------------------------------------------------ code FouLove

  /// Délai après la 5e erreur : 30 s, puis double à chaque erreur, jusqu'à 1 h.
  static Duration _delay(int failures) =>
      failures < 5 ? Duration.zero : Duration(seconds: min(3600, 30 * pow(2, failures - 5).toInt()));

  Duration get remaining {
    final w = waitUntil;
    if (w == null) return Duration.zero;
    final d = w.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Future<bool> _check(String pin) async {
    final stored = _pin;
    if (stored == null || remaining > Duration.zero) return false;
    final ok = await lockPinVerify(pin: pin, stored: stored);
    if (ok) {
      failures = 0;
      waitUntil = null;
      await _store.delete(key: _failKey);
      await _store.delete(key: _untilKey);
    } else {
      failures++;
      final d = _delay(failures);
      waitUntil = d == Duration.zero ? null : DateTime.now().add(d);
      await _store.write(key: _failKey, value: '$failures');
      if (waitUntil != null) await _store.write(key: _untilKey, value: waitUntil!.toIso8601String());
    }
    notifyListeners();
    return ok;
  }

  /// Essaie un code sur l'écran verrouillé.
  Future<bool> unlockWithPin(String pin) async {
    final ok = await _check(pin);
    if (ok) _unlocked();
    return ok;
  }

  /// Vérifie le code actuel (avant de le changer ou de le retirer).
  Future<bool> verifyPin(String pin) => _check(pin);

  Future<void> setPin(String pin) async {
    final h = await lockPinHash(pin: pin);
    if (h == null) throw ArgumentError('6 chiffres');
    _pin = h;
    await _store.write(key: _pinKey, value: h);
    await _hideInRecents(true);
    notifyListeners();
  }

  Future<void> removePin() async {
    _pin = null;
    await _store.delete(key: _pinKey);
    await _hideInRecents(enabled);
    notifyListeners();
  }

  /// Empreinte / visage / code du téléphone. Le changer demande de s'authentifier : sinon, quelqu'un qui
  /// tient le téléphone déverrouillé pourrait le couper en un geste.
  Future<bool> setBiometrics(bool on) async {
    if (on == biometrics) return true;
    if (!supported) return false;
    if (!await _authenticate(on ? 'Confirme pour ouvrir FouLove ainsi' : 'Confirme pour désactiver')) return false;
    biometrics = on;
    await _store.write(key: _pref, value: on ? 'on' : 'off');
    await _hideInRecents(enabled);
    notifyListeners();
    return true;
  }

  /// Code oublié : on se reconnecte (e-mail), et le code est retiré.
  Future<void> forgot() async {
    await onForgot?.call();
    await removePin();
    failures = 0;
    waitUntil = null;
    await _store.delete(key: _failKey);
    await _store.delete(key: _untilKey);
    _unlocked();
  }

  Future<void> _hideInRecents(bool hide) async {
    if (!Platform.isAndroid) return;
    try {
      await _native.invokeMethod<void>('hideInRecents', hide);
    } catch (_) {}
  }
}

/// Recouvre toute l'app tant qu'elle est verrouillée (seulement quand quelqu'un est connecté).
class LockGate extends StatelessWidget {
  const LockGate({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lock = AppLock.instance;
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => Stack(
        children: [
          child,
          if (active && lock.locked) const Positioned.fill(child: _LockScreen()),
        ],
      ),
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen();

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  AppLock get _lock => AppLock.instance;

  @override
  void initState() {
    super.initState();
    // Propose tout de suite l'empreinte, sans toucher de bouton.
    WidgetsBinding.instance.addPostFrameCallback((_) => _lock.unlockWithBiometrics());
  }

  Future<void> _forgot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Code oublié ?'),
        content: const Text(
          'Pour ta sécurité, il faut te reconnecter avec ton adresse e-mail. Le code sera retiré ; '
          'tu pourras en choisir un nouveau dans les réglages.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Me reconnecter')),
        ],
      ),
    );
    if (ok == true) await _lock.forgot();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surface,
      child: LoveBackground(
        count: 10,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
            child: _lock.hasPin
                ? Column(
                    children: [
                      const Spacer(),
                      const BeatingHeart(size: 54),
                      const SizedBox(height: 14),
                      Text('Ton code FouLove', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 24),
                      PinPad(
                        onDone: _lock.unlockWithPin,
                        biometrics: _lock.biometrics ? _lock.unlockWithBiometrics : null,
                      ),
                      const Spacer(),
                      TextButton(onPressed: _forgot, child: const Text('Code oublié ?')),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      const Center(child: EntwinedHeart(size: 170)),
                      const SizedBox(height: 18),
                      Text(
                        'Votre bulle est fermée à clé',
                        textAlign: TextAlign.center,
                        style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Seul toi peux l\'ouvrir, avec ton empreinte, ton visage ou le code de ton téléphone.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.4),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: const Text('Déverrouiller'),
                        onPressed: _lock.unlockWithBiometrics,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Saisie d'un code à 6 chiffres : six points, un clavier rond, une secousse si c'est faux.
/// `onDone` renvoie vrai si le code est accepté. Affiche l'attente imposée après plusieurs erreurs.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onDone, this.biometrics, this.hint});

  final Future<bool> Function(String pin) onDone;
  final VoidCallback? biometrics;

  /// Texte sous les points (sinon : « Code incorrect » après une erreur).
  final String? hint;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _busy = false;
  bool _wrong = false;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Compte à rebours de l'attente imposée.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && AppLock.instance.waitUntil != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _press(String d) async {
    if (_busy || _pin.length >= 6 || AppLock.instance.remaining > Duration.zero) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _wrong = false;
    });
    if (_pin.length < 6) return;
    setState(() => _busy = true);
    final ok = await widget.onDone(_pin);
    if (!mounted) return;
    if (!ok) {
      HapticFeedback.heavyImpact();
      await _shake.forward(from: 0);
    }
    if (mounted) {
      setState(() {
        _pin = '';
        _busy = false;
        _wrong = !ok;
      });
    }
  }

  void _back() {
    if (_pin.isEmpty || _busy) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final wait = AppLock.instance.remaining;
    final message = wait > Duration.zero
        ? 'Trop d\'essais. Réessaie dans ${wait.inMinutes > 0 ? '${wait.inMinutes} min ' : ''}${wait.inSeconds % 60} s'
        : (widget.hint != null && widget.hint!.isNotEmpty ? widget.hint! : (_wrong ? 'Code incorrect' : ''));
    final alert = wait > Duration.zero || _wrong;

    Widget key(Widget child, {VoidCallback? onTap, required String label, bool plain = false}) => Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Container(
          width: 74,
          height: 74,
          alignment: Alignment.center,
          decoration: plain ? null : BoxDecoration(shape: BoxShape.circle, color: context.love.surface2),
          child: child,
        ),
      ),
    );
    Widget digit(String d) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: key(
        Text(
          d,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500, color: cs.onSurface),
        ),
        onTap: () => _press(d),
        label: d,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (_, child) => Transform.translate(
            offset: Offset(sin(_shake.value * pi * 6) * 12 * (1 - _shake.value), 0),
            child: child,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 6; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? cs.primary : Colors.transparent,
                    border: Border.all(color: i < _pin.length ? cs.primary : cs.onSurfaceVariant, width: 1.6),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 20,
          child: Text(message, style: TextStyle(color: alert ? cs.error : cs.onSurfaceVariant)),
        ),
        const SizedBox(height: 18),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) digit(d)]),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: widget.biometrics == null
                  ? const SizedBox(width: 74, height: 74)
                  : key(
                      Icon(Icons.fingerprint_rounded, size: 34, color: cs.primary),
                      onTap: widget.biometrics,
                      label: 'Empreinte',
                      plain: true,
                    ),
            ),
            digit('0'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: key(
                Icon(Icons.backspace_outlined, color: cs.onSurfaceVariant),
                onTap: _back,
                label: 'Effacer',
                plain: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Choisir (ou changer) le code FouLove : le taper deux fois.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String? _first;
  String? _hint;

  Future<bool> _done(String pin) async {
    if (_first == null) {
      setState(() {
        _first = pin;
        _hint = null;
      });
      return true;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _hint = 'Les deux codes ne correspondent pas. Recommence.';
      });
      return false;
    }
    await AppLock.instance.setPin(pin);
    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Code FouLove activé ♡ Il sera demandé à chaque ouverture.')));
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Code FouLove')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Text(
                _first == null ? 'Choisis 6 chiffres' : 'Encore une fois',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Propre à FouLove, différent du code de ton téléphone. Évite ta date de naissance.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 24),
              PinPad(key: ValueKey(_first == null), onDone: _done, hint: _hint),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Demande le code actuel (avant de le changer ou de le retirer). Renvoie vrai s'il est juste.
Future<bool> askCurrentPin(BuildContext context) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Ton code actuel')),
        body: SafeArea(
          child: Center(
            child: PinPad(
              onDone: (p) async {
                final good = await AppLock.instance.verifyPin(p);
                if (good && context.mounted) Navigator.pop(context, true);
                return good;
              },
            ),
          ),
        ),
      ),
    ),
  );
  return ok == true;
}
