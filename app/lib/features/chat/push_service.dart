import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Notifications « Nouveau message » (docs/SECURITY.md §9).
///
/// Le serveur envoie un texte fixe, sans contenu ni nom : il n'y a rien à déchiffrer ici. L'app enregistre seulement
/// l'identifiant d'installation Firebase (FID) de ce téléphone, cible d'envoi recommandée par FCM, et efface les notifications affichées quand la conversation est ouverte.
/// App au premier plan : Android n'affiche pas la notification, la conversation se met à jour en temps réel.
abstract final class PushService {
  static const _native = MethodChannel('foulove/notifications');
  static StreamSubscription<String>? _refresh;
  static String? _token;
  static bool _ready = false;

  static Future<bool> _init() async {
    if (_ready) return true;
    // Android seulement pour l'instant : l'iPhone demandera la configuration APNs (étape iOS).
    if (!Platform.isAndroid) return false;
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] Firebase : $e');
    }
    return _ready;
  }

  /// Demande l'autorisation (Android 13+) et enregistre le jeton pour le compte connecté.
  static Future<void> register(SupabaseClient db) async {
    if (!await _init()) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // onRegistered donne le FID à l'inscription, puis à chaque renouvellement.
      await _refresh?.cancel();
      _refresh = FirebaseMessaging.instance.onRegistered.listen((fid) => _save(db, fid));
      await FirebaseMessaging.instance.register();
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] notifications : $e');
    }
  }

  static Future<void> _save(SupabaseClient db, String token) async {
    _token = token;
    await db.rpc<void>('register_push_token', params: {'token': token, 'platform': 'android'});
  }

  /// Déconnexion : ce téléphone ne doit plus rien recevoir pour ce compte.
  static Future<void> unregister(SupabaseClient db) async {
    if (!_ready) return;
    try {
      await _refresh?.cancel();
      _refresh = null;
      final t = _token;
      if (t != null) await db.rpc<void>('unregister_push_token', params: {'token': t});
      await FirebaseMessaging.instance.unregister();
      _token = null;
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] notifications : $e');
    }
  }

  /// Efface les notifications affichées (la conversation est à l'écran).
  static Future<void> clear() async {
    if (!Platform.isAndroid) return;
    try {
      await _native.invokeMethod<void>('clear');
    } catch (_) {}
  }
}
