import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'couple_service.dart';

/// Liens touchés hors de l'app (WhatsApp, SMS, appareil photo, site) qui ouvrent FouLove :
/// - une **invitation** (`…/rejoindre/#2.…`) : gardée jusqu'à ce qu'elle serve, même si la personne doit d'abord
///   se connecter (et même si l'app est fermée entre-temps, pendant 24 h) ;
/// - un **lien de retrouvailles** (`…/lien/#…`) : remis à l'écran de vérification ouvert.
///
/// Rien n'est envoyé ailleurs : le lien ne sert qu'ici, puis il est oublié.
abstract final class IncomingLinks {
  static final invitation = ValueNotifier<String?>(null);
  static final idLink = ValueNotifier<String?>(null);

  static const _store = FlutterSecureStorage();
  static const _key = 'foulov.pending_invitation';
  static const _ttl = Duration(hours: 24);
  static StreamSubscription<Uri>? _sub;

  static Future<void> init() async {
    try {
      final saved = (await _store.read(key: _key))?.split('|');
      if (saved != null && saved.length == 2) {
        final at = DateTime.fromMillisecondsSinceEpoch(int.tryParse(saved[0]) ?? 0);
        if (DateTime.now().difference(at) < _ttl) {
          invitation.value = saved[1];
        } else {
          await _store.delete(key: _key);
        }
      }
      final links = AppLinks();
      _sub = links.uriLinkStream.listen(_handle, onError: (_) {});
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] liens : $e');
    }
  }

  static Future<void> _handle(Uri uri) async {
    final text = uri.toString();
    if (CoupleService.isFullInvitation(text)) {
      invitation.value = text;
      await _store.write(key: _key, value: '${DateTime.now().millisecondsSinceEpoch}|$text');
    } else if (CoupleService.isIdLink(text)) {
      idLink.value = text;
    }
  }

  /// L'invitation a servi (ou a été refusée) : on l'oublie.
  static Future<void> clearInvitation() async {
    invitation.value = null;
    await _store.delete(key: _key);
  }

  static void dispose() => _sub?.cancel();
}
