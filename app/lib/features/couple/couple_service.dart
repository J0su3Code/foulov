import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../src/rust/api/chat.dart';
import '../../src/rust/api/crypto.dart';
import '../../src/rust/api/device.dart';

/// État du couple vu par ce téléphone.
class CoupleState {
  const CoupleState({this.coupleId, this.partnerId, this.partnerIdentity, this.verified = false, this.since});

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
  bool _opened = false;

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

  Future<CoupleState> load() async {
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
    return CoupleState(
      coupleId: coupleId,
      since: since,
      partnerId: partner,
      partnerIdentity: identity,
      verified: identity != null && await deviceIsVerified(partner: partner),
    );
  }

  // ------------------------------------------------------------------ créer / rejoindre

  /// Crée l'espace, publie les clés de ce téléphone et renvoie le code d'invitation (10 caractères).
  Future<String> createCouple() async {
    await openDevice();
    // Les clés publiques d'abord : sans elles, le partenaire ne pourrait pas ouvrir de session.
    await ensureKeysPublished();
    final code = await _db.rpc<String>('create_couple');
    await _keyStore.write(key: _inviteName, value: '$code|${DateTime.now().toIso8601String()}');
    return code;
  }

  static const _inviteName = 'foulov.invitation';

  /// Code d'invitation en cours. Le serveur n'en garde que le hachage : ce téléphone conserve le code lui-même
  /// (dans le coffre du système) pour qu'il reste identique tant qu'il est valable.
  Future<String> currentInvitation({bool forceNew = false}) async {
    final saved = await _keyStore.read(key: _inviteName);
    if (!forceNew && saved != null) {
      final parts = saved.split('|');
      final created = DateTime.tryParse(parts.last);
      if (parts.length == 2 && created != null && DateTime.now().difference(created) < const Duration(hours: 23)) {
        return parts.first;
      }
    }
    final code = await _db.rpc<String>('renew_invitation');
    await _keyStore.write(key: _inviteName, value: '$code|${DateTime.now().toIso8601String()}');
    return code;
  }

  /// Contenu du QR code : code d'invitation + empreinte de la clé d'identité de ce téléphone.
  Future<String> qrPayload(String code) async {
    final fp = await deviceFingerprint();
    return '$qrPrefix$code:${base64Url.encode(fp).replaceAll('=', '')}';
  }

  /// Rejoint avec un code tapé ou scanné. Avec un QR code, la clé du partenaire est vérifiée automatiquement.
  Future<JoinResult> join(String input) async {
    await openDevice();
    String code = input;
    Uint8List? expectedFp;
    if (input.startsWith(qrPrefix)) {
      final parts = input.substring(qrPrefix.length).split(':');
      if (parts.length != 2) return JoinResult.invalidCode;
      code = parts[0];
      expectedFp = base64Url.decode(base64Url.normalize(parts[1]));
    }
    await ensureKeysPublished();
    final coupleId = await _db.rpc<String?>('join_couple', params: {'token': code});
    if (coupleId == null) return JoinResult.invalidCode;

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
    final env = await deviceEncrypt(partner: partner, plaintext: utf8.encode(_hello));
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
    final rows = await _db.from('envelopes').select('id, kind, ciphertext').eq('sender_id', partner).order('created_at');
    final done = <String>[];
    for (final row in rows) {
      final id = row['id'] as String;
      await chatReceive(partner: partner, envelopeId: id, envelope: Envelope(kind: row['kind'] as int, body: _bytes(row['ciphertext'])));
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
