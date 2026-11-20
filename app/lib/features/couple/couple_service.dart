import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../src/rust/api/chat.dart';
import '../account/account_service.dart';
import '../backup/backup_service.dart';
import '../../src/rust/api/crypto.dart';
import '../../src/rust/api/device.dart';

/// État du couple vu par ce téléphone.
class CoupleState {
  const CoupleState({
    this.coupleId,
    this.partnerId,
    this.partnerIdentity,
    this.verified = false,
    this.since,
    this.keyChanged = false,
    this.restoreFrom,
    this.ended = false,
  });

  /// Ce téléphone avait un espace, et le serveur dit qu'il n'existe plus : l'autre a fermé la bulle (ou supprimé
  /// son compte). L'historique est encore ici, à effacer avant de recommencer.
  final bool ended;

  /// La clé publiée par le partenaire n'est plus celle en laquelle ce téléphone a confiance (nouveau téléphone,
  /// réinstallation… ou substitution par le serveur) : rien de nouveau n'est lu avant une nouvelle vérification.
  final bool keyChanged;

  /// Une sauvegarde chiffrée existe pour ce compte et ce téléphone n'a encore aucun historique : on propose de la
  /// restaurer (date de la sauvegarde).
  final DateTime? restoreFrom;

  final String? coupleId;

  /// Création de l'espace (« Jour N »).
  final DateTime? since;
  final String? partnerId;
  final Uint8List? partnerIdentity;
  final bool verified;

  bool get hasCouple => coupleId != null;
  bool get complete => partnerId != null;
}

/// Résultat d'une tentative pour rejoindre un couple.
enum JoinResult { joined, invalidCode, keyMismatch }

/// Appairage et premier message chiffré (docs/SECURITY.md §5).
///
/// Toute la cryptographie est dans le cœur Rust ; ce service transporte uniquement des clés publiques
/// et des enveloppes chiffrées vers Supabase.
class CoupleService {
  CoupleService(this._db);

  final SupabaseClient _db;
  static const _keyStore = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const _dbKeyName = 'foulov.device.db_key';
  static const _hello = 'FOULOVE:BONJOUR:1';
  static const qrPrefix = 'foulove:1:';

  /// Invitation complète (QR code ou message) : code, empreinte de la clé de celui qui invite, secret (§5).
  static const invitePrefix = 'foulove:2:';

  /// Lien de retrouvailles : l'empreinte de la clé de ce téléphone, à envoyer par une autre messagerie.
  static const idPrefix = 'foulove:id:';
  bool _opened = false;

  /// Le dernier « rejoindre » s'est fait avec l'invitation complète : les deux clés se vérifient sans symboles.
  bool joinedWithInvitation = false;

  String get _me => _db.auth.currentUser!.id;

  // ------------------------------------------------------------------ base locale

  /// Ouvre la base chiffrée du téléphone. Sa clé (256 bits) est créée une fois puis gardée par le Keystore / Keychain.
  Future<void> openDevice() async {
    if (_opened) return;
    var b64 = await _keyStore.read(key: _dbKeyName);
    if (b64 == null) {
      final r = Random.secure();
      b64 = base64Encode(List<int>.generate(32, (_) => r.nextInt(256)));
      await _keyStore.write(key: _dbKeyName, value: b64);
    }
    final dir = await getApplicationSupportDirectory();
    await deviceOpen(path: '${dir.path}/foulove.db', dbKey: base64Decode(b64));
    _opened = true;
  }

  // ------------------------------------------------------------------ état

  static const _cacheName = 'foulov.couple_cache';

  /// Dernier état complet connu (couple, partenaire, sa clé, vérifiée) : de quoi ouvrir l'app tout de suite, même
  /// hors ligne. Rangé dans le coffre du système. `null` s'il n'y en a pas, ou s'il faut repasser par le serveur.
  Future<CoupleState?> cached() async {
    await openDevice();
    final raw = await _keyStore.read(key: _cacheName);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      // Seulement pour le compte qui l'a enregistré.
      if (j['user'] != _me) return null;
      final identity = base64Decode(j['identity'] as String);
      // La clé gardée doit toujours être celle en laquelle ce téléphone a confiance.
      final trusted = await deviceTrustedIdentity(partner: j['partner'] as String);
      if (trusted == null || !_same(trusted, identity)) return null;
      return CoupleState(
        coupleId: j['couple'] as String,
        partnerId: j['partner'] as String,
        partnerIdentity: identity,
        verified: await deviceIsVerified(partner: j['partner'] as String),
        since: DateTime.tryParse(j['since'] as String? ?? '')?.toLocal(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _remember(CoupleState s) async {
    if (!s.complete || s.partnerIdentity == null || s.keyChanged || s.restoreFrom != null) {
      await _keyStore.delete(key: _cacheName);
      return;
    }
    await _keyStore.write(
      key: _cacheName,
      value: jsonEncode({
        'user': _me,
        'couple': s.coupleId,
        'partner': s.partnerId,
        'identity': base64Encode(s.partnerIdentity!),
        'since': s.since?.toUtc().toIso8601String(),
      }),
    );
  }

  Future<void> forgetCache() => _keyStore.delete(key: _cacheName);

  /// État à jour, lu sur le serveur (et gardé pour la prochaine ouverture).
  /// À qui appartient ce que contient ce téléphone : « compte|espace ». Gardé même après une déconnexion (l'historique
  /// reste sur le téléphone) ; effacé seulement avec ces données (`AccountService.wipeLocal`).
  static const ownerName = 'foulov.local_owner';

  Future<CoupleState> load() async {
    final owner = (await _keyStore.read(key: ownerName))?.split('|');
    if (owner != null && owner.first != _me) {
      // Un autre compte se connecte sur ce téléphone : il ne doit jamais voir l'historique du précédent.
      await AccountService.wipeLocal();
      reset();
      return load();
    }
    final s = await _load();
    // Ce téléphone garde l'historique d'un espace qui n'existe plus (ou d'un autre espace) : à effacer d'abord.
    if (owner != null && (!s.hasCouple || (s.complete && owner.last != s.coupleId))) {
      return const CoupleState(ended: true);
    }
    // Téléphone installé avant ce suivi : pas d'espace, mais un ancien historique encore là.
    if (owner == null && !s.hasCouple && (await chatMessages(limit: 1)).isNotEmpty) {
      return const CoupleState(ended: true);
    }
    if (s.complete) await _keyStore.write(key: ownerName, value: '$_me|${s.coupleId}');
    await _remember(s);
    return s;
  }

  /// Bulle créée mais personne ne l'a encore rejointe : on l'annule (rien à perdre, elle est vide) pour revenir au
  /// choix « créer / rejoindre ».
  Future<void> cancelPendingCouple() async {
    await _db.rpc<dynamic>('leave_couple');
    await _keyStore.delete(key: _inviteName);
  }

  /// Après une remise à zéro (bulle fermée) : la prochaine ouverture crée une base et des clés neuves.
  void reset() {
    _opened = false;
    joinedWithInvitation = false;
  }

  Future<CoupleState> _load() async {
    await openDevice();
    final rows = await _db.from('couple_members').select('couple_id, user_id');
    if (rows.isEmpty) return const CoupleState();
    await ensureKeysPublished();
    final coupleId = rows.first['couple_id'] as String;
    final couple = await _db.from('couples').select('created_at').eq('id', coupleId).maybeSingle();
    final since = DateTime.tryParse(couple?['created_at'] as String? ?? '')?.toLocal();
    final partner = rows.map((r) => r['user_id'] as String).where((u) => u != _me).firstOrNull;
    if (partner == null) return CoupleState(coupleId: coupleId, since: since);
    final dev = await _db.from('devices').select('identity_key').eq('user_id', partner).maybeSingle();
    final identity = dev == null ? null : _bytes(dev['identity_key']);
    final trusted = await deviceTrustedIdentity(partner: partner);
    final keyChanged = identity != null && trusted != null && !_same(trusted, identity);
    DateTime? restoreFrom;
    if (identity != null && !keyChanged) {
      restoreFrom = await _restoreOffer();
      // Nouveau téléphone ou réinstallation : on rouvre la session chiffrée (après la restauration éventuelle).
      if (restoreFrom == null) await _ensureSession(partner);
    }
    return CoupleState(
      coupleId: coupleId,
      since: since,
      partnerId: partner,
      partnerIdentity: identity,
      verified: identity != null && !keyChanged && await deviceIsVerified(partner: partner),
      keyChanged: keyChanged,
      restoreFrom: restoreFrom,
    );
  }

  static const _restoreOfferedKey = 'foulov.restore_offered';

  /// Proposée une seule fois : sur un téléphone sans historique, quand une sauvegarde existe pour ce compte.
  Future<DateTime?> _restoreOffer() async {
    if (await _keyStore.read(key: _restoreOfferedKey) != null) return null;
    if ((await chatMessages(limit: 1)).isNotEmpty) {
      await _keyStore.write(key: _restoreOfferedKey, value: 'non');
      return null;
    }
    final DateTime? at;
    try {
      at = await BackupService.instance.remoteBackupDate(_db);
    } catch (e) {
      // Réseau indisponible : on reposera la question au prochain chargement, sans rien conclure.
      if (kDebugMode) debugPrint('[FOULOVE] sauvegarde distante : $e');
      return null;
    }
    if (at == null) await _keyStore.write(key: _restoreOfferedKey, value: 'non');
    return at;
  }

  /// Après la restauration, ou si l'utilisateur la refuse : on ne la repropose plus.
  Future<void> restoreDone() => _keyStore.write(key: _restoreOfferedKey, value: 'oui');

  /// Aucune session avec le partenaire (nouveau téléphone) : d'abord lire ce qui attend sur le serveur (son premier
  /// message peut l'ouvrir), sinon l'ouvrir nous-mêmes à partir de ses clés publiées.
  Future<void> _ensureSession(String partner) async {
    if (await deviceHasSession(partner: partner)) return;
    try {
      await receiveHello(partner);
      if (await deviceHasSession(partner: partner)) return;
      await _openSession();
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] session : $e');
    }
  }

  /// Nouvelle clé du partenaire acceptée après comparaison des 7 symboles : les messages en attente se lisent.
  Future<void> acceptPartnerKey(String partner, Uint8List identity) async {
    await deviceAcceptPartnerKey(partner: partner, identityKey: identity);
    await deviceMarkVerified(partner: partner);
  }

  // ------------------------------------------------------------------ créer / rejoindre

  /// Crée l'espace, publie les clés de ce téléphone et renvoie le code d'invitation (10 caractères).
  Future<String> createCouple() async {
    await openDevice();
    // Les clés publiques d'abord : sans elles, le partenaire ne pourrait pas ouvrir de session.
    await ensureKeysPublished();
    final code = await _db.rpc<String>('create_couple');
    await _saveInvitation(code);
    return code;
  }

  static const _inviteName = 'foulov.invitation';

  /// Code d'invitation en cours. Le serveur n'en garde que le hachage : ce téléphone conserve le code lui-même
  /// (dans le coffre du système) pour qu'il reste identique tant qu'il est valable.
  Future<String> currentInvitation({bool forceNew = false}) async {
    final saved = await _keyStore.read(key: _inviteName);
    if (!forceNew && saved != null) {
      final parts = saved.split('|');
      final created = parts.length == 3 ? DateTime.tryParse(parts[1]) : null;
      if (created != null && DateTime.now().difference(created) < const Duration(hours: 23)) return parts.first;
    }
    final code = await _db.rpc<String>('renew_invitation');
    await _saveInvitation(code);
    return code;
  }

  /// Le code (dont le serveur ne garde que le hachage) et un secret de 128 bits qui ne quitte jamais ce téléphone,
  /// sauf dans l'invitation elle-même.
  Future<void> _saveInvitation(String code) async {
    final r = Random.secure();
    final secret = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256))).replaceAll('=', '');
    await _keyStore.write(key: _inviteName, value: '$code|${DateTime.now().toIso8601String()}|$secret');
  }

  Future<Uint8List?> _inviteSecret() async {
    final parts = (await _keyStore.read(key: _inviteName))?.split('|');
    if (parts == null || parts.length != 3) return null;
    return base64Url.decode(base64Url.normalize(parts[2]));
  }

  /// Invitation complète : code, empreinte de ma clé, secret. Sert au QR code et au message envoyé à distance.
  Future<String> invitation(String code) async {
    final fp = base64Url.encode(await deviceFingerprint()).replaceAll('=', '');
    final secret = base64Url.encode(await _inviteSecret() ?? Uint8List(0)).replaceAll('=', '');
    return '$invitePrefix$code:$fp:$secret';
  }

  /// Message à envoyer par WhatsApp, SMS… : il suffit de le copier puis de le coller dans FouLove.
  Future<String> invitationText(String code) async =>
      'Rejoins-moi sur FouLove 💞\n'
      'Installe l\'app et connecte-toi. Touche « J\'ai reçu une invitation », puis « Coller ou saisir » et '
      '« Coller l\'invitation ».\n\n'
      '${await invitation(code)}';

  /// Chez celui qui a invité, après le premier message : la preuve reçue vient-elle de la personne qui a reçu
  /// l'invitation ? Si oui, sa clé est vérifiée, sans symboles. L'invitation, utilisée, est oubliée.
  Future<bool> verifyJoinProof(String partner) async {
    final secret = await _inviteSecret();
    if (secret == null) return false;
    final ok = await deviceVerifyJoinProof(partner: partner, secret: secret);
    if (ok) await _keyStore.delete(key: _inviteName);
    return ok;
  }

  /// Lit une invitation dans un texte collé ou scanné : (code, empreinte attendue, secret), ou `null`.
  static (String, Uint8List?, Uint8List?)? parseInvitation(String text) {
    Uint8List b64(String s) => base64Url.decode(base64Url.normalize(s));
    final v2 = RegExp(r'foulove:2:([0-9A-Za-z-]{10,11}):([A-Za-z0-9_-]{20,}):([A-Za-z0-9_-]{20,})').firstMatch(text);
    if (v2 != null) {
      try {
        return (v2.group(1)!.replaceAll('-', ''), b64(v2.group(2)!), b64(v2.group(3)!));
      } catch (_) {
        return null;
      }
    }
    final v1 = RegExp(r'foulove:1:([0-9A-Za-z-]{10,11}):([A-Za-z0-9_-]{20,})').firstMatch(text);
    if (v1 != null) {
      try {
        return (v1.group(1)!.replaceAll('-', ''), b64(v1.group(2)!), null);
      } catch (_) {
        return null;
      }
    }
    final code = text.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    return code.length == 10 ? (code, null, null) : null;
  }

  // ------------------------------------------------------------------ retrouvailles (nouveau téléphone)

  /// Mon lien de retrouvailles : l'empreinte de ma clé, à envoyer par une autre messagerie.
  Future<String> fingerprintLink() async =>
      'Voici mon lien FouLove 💞 Copie ce message, puis touche « Coller son lien » dans FouLove.\n\n'
      '$idPrefix${base64Url.encode(await deviceFingerprint()).replaceAll('=', '')}';

  /// Son lien de retrouvailles, collé : s'il correspond à sa clé, elle est acceptée et vérifiée sans symboles.
  /// Renvoie faux si le lien ne correspond pas (ou n'en est pas un).
  Future<bool> acceptByLink(String partner, Uint8List identity, String text, {bool keyChange = false}) async {
    final m = RegExp(r'foulove:id:([A-Za-z0-9_-]{20,})').firstMatch(text);
    if (m == null) return false;
    final Uint8List fp;
    try {
      fp = base64Url.decode(base64Url.normalize(m.group(1)!));
    } catch (_) {
      return false;
    }
    if (!_same(fingerprintOf(identityKey: identity), fp)) return false;
    if (keyChange) {
      await acceptPartnerKey(partner, identity);
    } else {
      await deviceMarkVerified(partner: partner);
    }
    return true;
  }

  /// Contenu du QR code : l'invitation complète (le même contenu que le message envoyé à distance).
  Future<String> qrPayload(String code) => invitation(code);

  /// Rejoint avec une invitation collée ou scannée (ou un code tapé). Avec l'invitation complète, la clé de l'autre
  /// est vérifiée ici automatiquement, et la preuve envoyée lui permet de vérifier la mienne : pas de symboles.
  Future<JoinResult> join(String input) async {
    await openDevice();
    final parsed = parseInvitation(input);
    if (parsed == null) return JoinResult.invalidCode;
    final (code, expectedFp, secret) = parsed;
    await ensureKeysPublished();
    final coupleId = await _db.rpc<String?>('join_couple', params: {'token': code});
    if (coupleId == null) return JoinResult.invalidCode;
    final r = await _openSession(expectedFp: expectedFp, secret: secret);
    joinedWithInvitation = r == JoinResult.joined && secret != null && expectedFp != null;
    return r;
  }

  /// Ouvre la session à partir des clés publiées du partenaire (PQXDH), puis lui envoie le premier message chiffré,
  /// qui ouvre la session de son côté. Avec un QR code, la clé est vérifiée contre son empreinte.
  Future<JoinResult> _openSession({Uint8List? expectedFp, Uint8List? secret}) async {
    final coupleId = (await _db.from('couple_members').select('couple_id').limit(1).single())['couple_id'] as String;
    final rows = await _db.rpc<List<dynamic>>('claim_partner_bundle');
    final r = rows.first as Map<String, dynamic>;
    final partner = r['user_id'] as String;
    final bundle = KeyBundle(
      registrationId: r['registration_id'] as int,
      deviceId: r['device_id'] as int,
      identityKey: _bytes(r['identity_key']),
      signedPrekeyId: r['signed_prekey_id'] as int,
      signedPrekey: _bytes(r['signed_prekey']),
      signedPrekeySig: _bytes(r['signed_prekey_sig']),
      kyberPrekeyId: r['kyber_prekey_id'] as int,
      kyberPrekey: _bytes(r['kyber_prekey']),
      kyberPrekeySig: _bytes(r['kyber_prekey_sig']),
      oneTimePrekeys: [
        if (r['one_time_prekey_id'] != null)
          OneTimePreKey(id: r['one_time_prekey_id'] as int, publicKey: _bytes(r['one_time_prekey'])),
      ],
    );
    if (expectedFp != null && !_same(fingerprintOf(identityKey: bundle.identityKey), expectedFp)) {
      // La clé publiée par le serveur n'est pas celle du téléphone qui a montré le QR code.
      return JoinResult.keyMismatch;
    }
    await deviceStartSession(partner: partner, bundle: bundle);
    if (expectedFp != null) await deviceMarkVerified(partner: partner);

    // Premier message chiffré de bout en bout : il établit la session chez le partenaire.
    // Avec une invitation complète, il porte aussi la preuve tirée de son secret.
    final hello = secret != null && expectedFp != null
        ? await deviceJoinHello(partner: partner, secret: secret)
        : utf8.encode(_hello);
    final env = await deviceEncrypt(partner: partner, plaintext: hello);
    await _db.from('envelopes').insert({
      'couple_id': coupleId,
      'sender_id': _me,
      'recipient_id': partner,
      'kind': env.kind,
      'ciphertext': _hex(env.body),
    });
    return JoinResult.joined;
  }

  /// Reçoit et déchiffre le premier message du partenaire (côté créateur). Renvoie vrai si la session est établie.
  /// Passe par la même file que la messagerie (`chatReceive`) : atomique, sans doublon, et un éventuel
  /// premier mot doux arrivé avec le message d'appairage est conservé dans l'historique.
  Future<bool> receiveHello(String partner) async {
    if (await deviceHasSession(partner: partner)) return true;
    final rows = await _db
        .from('envelopes')
        .select('id, kind, ciphertext')
        .eq('sender_id', partner)
        .order('created_at');
    final done = <String>[];
    for (final row in rows) {
      final id = row['id'] as String;
      await chatReceive(
        partner: partner,
        envelopeId: id,
        envelope: Envelope(kind: row['kind'] as int, body: _bytes(row['ciphertext'])),
      );
      done.add(id);
    }
    if (done.isNotEmpty) await _db.from('envelopes').delete().inFilter('id', done);
    return deviceHasSession(partner: partner);
  }

  Future<List<SasSymbol>> symbols(Uint8List partnerIdentity) => deviceSasWith(partnerIdentity: partnerIdentity);

  Future<void> confirmSymbols(String partner) => deviceMarkVerified(partner: partner);

  // ------------------------------------------------------------------ outils

  /// Publie les clés de ce téléphone si le serveur ne les a pas encore (ou plus) : opération idempotente.
  Future<void> ensureKeysPublished() async {
    await openDevice();
    final mine = await _db.from('devices').select('identity_key').eq('user_id', _me).maybeSingle();
    final local = await deviceIdentityKey();
    if (mine != null && _same(_bytes(mine['identity_key']), local)) return;
    try {
      await _publishKeys();
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] publication des clés : $e');
      rethrow;
    }
  }

  Future<void> _publishKeys() async {
    final b = await deviceGenerateBundle(oneTime: 20);
    await _db.from('devices').upsert({
      'user_id': _me,
      'registration_id': b.registrationId,
      'device_id': b.deviceId,
      'identity_key': _hex(b.identityKey),
      'signed_prekey_id': b.signedPrekeyId,
      'signed_prekey': _hex(b.signedPrekey),
      'signed_prekey_sig': _hex(b.signedPrekeySig),
      'kyber_prekey_id': b.kyberPrekeyId,
      'kyber_prekey': _hex(b.kyberPrekey),
      'kyber_prekey_sig': _hex(b.kyberPrekeySig),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    // Nouveau téléphone (ou nouvelle identité) : les pré-clés de l'ancien ne servent plus et porteraient les mêmes
    // numéros. On les retire, pour que le partenaire n'en tire jamais une qui ne mène nulle part.
    await _db.from('one_time_prekeys').delete().eq('user_id', _me);
    await _db.from('one_time_prekeys').insert([
      for (final k in b.oneTimePrekeys) {'user_id': _me, 'prekey_id': k.id, 'public_key': _hex(k.publicKey)},
    ]);
  }

  /// Format bytea de PostgREST : « \x » suivi de l'hexadécimal.
  static String _hex(List<int> b) => '\\x${b.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}';

  static Uint8List _bytes(dynamic v) {
    final s = (v as String).startsWith('\\x') ? v.substring(2) : v;
    return Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}
