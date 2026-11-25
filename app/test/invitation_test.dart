import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:foulov/features/couple/couple_service.dart';

void main() {
  // Comme dans l'app : empreinte de 32 octets et secret de 16 octets, en base64url sans « = ».
  final fp = base64Url.encode(List.generate(32, (i) => i * 7 % 256)).replaceAll('=', '');
  final secret = base64Url.encode(List.generate(16, (i) => 255 - i)).replaceAll('=', '');

  test('le lien d\'invitation se lit, dans un message WhatsApp entier', () {
    final msg = 'Rejoins-moi sur FouLove 💞 Touche ce lien :\nhttps://foulove.josuecode.com/rejoindre/#2.K7Q4M9XHPT.$fp.$secret';
    final p = CoupleService.parseInvitation(msg)!;
    expect(p.$1, 'K7Q4M9XHPT');
    expect(p.$2, isNotNull);
    expect(p.$3, isNotNull);
    expect(CoupleService.isFullInvitation(msg), isTrue);
  });

  test('le lien de secours foulove:// (page du site) se lit aussi', () {
    final url = 'foulove://rejoindre?i=2.K7Q4M9XHPT.$fp.$secret';
    expect(CoupleService.parseInvitation(url)!.$1, 'K7Q4M9XHPT');
    expect(CoupleService.isFullInvitation(url), isTrue);
  });

  test('les anciennes invitations restent acceptées', () {
    final old = 'foulove:2:K7Q4M-9XHPT:$fp:$secret';
    expect(CoupleService.parseInvitation(old)!.$1, 'K7Q4M9XHPT');
    expect(CoupleService.isFullInvitation(old), isTrue);
  });

  test('un code tapé seul n\'est pas une invitation complète', () {
    expect(CoupleService.parseInvitation('K7Q4M-9XHPT')!.$1, 'K7Q4M9XHPT');
    expect(CoupleService.isFullInvitation('K7Q4M-9XHPT'), isFalse);
    expect(CoupleService.isFullInvitation('https://foulove.josuecode.com/rejoindre/'), isFalse);
  });

  test('les liens de retrouvailles sont reconnus, ancien et nouveau format', () {
    expect(CoupleService.isIdLink('https://foulove.josuecode.com/lien/#$fp'), isTrue);
    expect(CoupleService.isIdLink('foulove://lien?i=$fp'), isTrue);
    expect(CoupleService.isIdLink('foulove:id:$fp'), isTrue);
    expect(CoupleService.isIdLink('bonjour'), isFalse);
  });
}
