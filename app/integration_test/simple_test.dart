// Tests sur un vrai appareil (ou émulateur) : vérifient que le cœur Rust est bien chargé et
// fonctionne sur le processeur du téléphone. Lancer : flutter test integration_test
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:foulov/src/rust/api/crypto.dart';
import 'package:foulov/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  test('le cœur Rust est chargé', () {
    expect(coreVersion(), isNotEmpty);
  });

  test('les 7 symboles sont identiques des deux côtés et figés', () {
    final a = Uint8List.fromList(List.filled(33, 0x05));
    final b = Uint8List.fromList(List.filled(33, 0x06));
    final ab = sasSymbols(identityA: a, identityB: b);
    final ba = sasSymbols(identityA: b, identityB: a);
    expect(ab.length, 7);
    expect(ab.map((s) => s.name).toList(), ba.map((s) => s.name).toList());
    // Même vecteur de référence que core/src/sas.rs : index [31, 18, 4, 44, 36, 6, 58].
    expect(ab.map((s) => s.name).toList(), ['Robot', 'Champignon', 'Licorne', 'Trombone', 'Pouce', 'Éléphant', 'Trompette']);
  });

  test("chiffrement d'une photo de 3 Mo : aller-retour et intégrité", () async {
    final rnd = Random(1);
    final photo = Uint8List.fromList(List.generate(3 * 1024 * 1024, (_) => rnd.nextInt(256)));
    final sw = Stopwatch()..start();
    final e = await encryptMedia(plaintext: photo);
    final back = await decryptMedia(key: e.key, ciphertext: e.ciphertext, sha256: e.sha256);
    sw.stop();
    expect(back, photo);
    expect(e.ciphertext.length, greaterThan(photo.length));
    // Un octet altéré : le déchiffrement doit échouer.
    final tampered = Uint8List.fromList(e.ciphertext)..[1000] ^= 1;
    expect(() => decryptMedia(key: e.key, ciphertext: tampered, sha256: e.sha256), throwsA(anything));
    // ignore: avoid_print
    print('chiffrement + déchiffrement de 3 Mo : ${sw.elapsedMilliseconds} ms');
  });
}
