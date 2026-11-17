import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../ui/love.dart';

/// Verrouillage de l'app (docs/SECURITY.md §7) : empreinte, visage ou code du téléphone,
/// à l'ouverture et après une minute en arrière-plan.
///
/// C'est un verrou d'accès à l'interface, comme celui de Signal. La clé de la base locale reste protégée par le
/// Keystore sans exiger d'authentification : sinon, retirer le verrouillage d'écran du téléphone détruirait la clé,
/// et tout l'historique avec.
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock._();
  static final instance = AppLock._();

  static const _pref = 'foulov.app_lock';
  static const _grace = Duration(minutes: 1);
  static const _store = FlutterSecureStorage();
  static const _native = MethodChannel('foulove/notifications');
  final _auth = LocalAuthentication();

  bool supported = false;
  bool enabled = false;
  bool locked = false;
  bool _authenticating = false;
  DateTime? _leftAt;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      supported = await _auth.isDeviceSupported();
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] verrouillage indisponible : $e');
      supported = false;
    }
    if (kDebugMode) debugPrint('[FOULOVE] verrouillage : appareil compatible = $supported');
    // Activé par défaut dès que le téléphone a un verrouillage d'écran.
    enabled = supported && (await _store.read(key: _pref)) != 'off';
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
    if (_authenticating) return false;
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

  Future<void> unlock() async {
    if (!locked) return;
    if (await _authenticate('Déverrouille FouLove')) {
      locked = false;
      notifyListeners();
    }
  }

  /// Désactiver le verrou demande de s'authentifier : sinon, quelqu'un qui tient le téléphone déverrouillé
  /// pourrait le couper en un geste.
  Future<bool> setEnabled(bool on) async {
    if (on == enabled) return true;
    if (!supported) return false;
    if (!on && !await _authenticate('Confirme pour désactiver le verrouillage')) return false;
    enabled = on;
    await _store.write(key: _pref, value: on ? 'on' : 'off');
    await _hideInRecents(on);
    notifyListeners();
    return true;
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
  @override
  void initState() {
    super.initState();
    // Propose tout de suite l'empreinte, sans toucher de bouton.
    WidgetsBinding.instance.addPostFrameCallback((_) => AppLock.instance.unlock());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surface,
      child: PetalBackground(
        count: 10,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Center(child: EntwinedHeart(size: 170)),
                const SizedBox(height: 18),
                Text(
                  'Votre jardin est fermé à clé',
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
                  onPressed: AppLock.instance.unlock,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
