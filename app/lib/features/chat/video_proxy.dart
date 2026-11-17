import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../src/rust/api/chat.dart';

/// Lecture des vidéos sans jamais les écrire en clair (docs/SECURITY.md §6).
///
/// Le lecteur vidéo du système ne sait lire qu'un fichier ou une adresse. On lui donne une adresse locale :
/// ce petit serveur, lié à 127.0.0.1 uniquement, déchiffre à la volée les plages demandées (`chatMediaRead`,
/// chaque bloc est authentifié) et les lui transmet. Rien n'est écrit sur le disque.
///
/// Chaque adresse contient un jeton aléatoire de 128 bits, propre à cette exécution de l'app : une autre
/// application du téléphone qui connaîtrait le port ne pourrait rien demander sans lui.
abstract final class VideoProxy {
  static HttpServer? _server;
  static String _token = '';

  static Future<Uri> url(String messageId) async {
    final s = _server ??= await _start();
    return Uri.parse('http://127.0.0.1:${s.port}/$_token/$messageId.mp4');
  }

  static Future<HttpServer> _start() async {
    final r = Random.secure();
    _token = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen(_handle, onError: (_) {});
    return s;
  }

  static bool _same(String a, String b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }

  static final _id = RegExp(r'^([0-9a-f]{32})\.mp4$');

  static Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final seg = req.uri.pathSegments;
      final m = seg.length == 2 ? _id.firstMatch(seg[1]) : null;
      if (req.method != 'GET' && req.method != 'HEAD' || m == null || !_same(seg[0], _token)) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final id = m.group(1)!;
      final total = (await chatMediaLen(messageId: id)).toInt();
      var start = 0, end = total - 1;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final rm = range == null ? null : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      if (rm != null) {
        final a = rm.group(1)!, b = rm.group(2)!;
        if (a.isEmpty && b.isNotEmpty) {
          start = max(0, total - int.parse(b)); // « les N derniers octets »
        } else {
          start = int.tryParse(a) ?? 0;
          if (b.isNotEmpty) end = min(int.parse(b), total - 1);
        }
        if (start >= total || start > end) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
          await res.close();
          return;
        }
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
      }
      res.headers
        ..contentType = ContentType('video', 'mp4')
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..contentLength = end - start + 1;
      if (req.method == 'GET') {
        var pos = start;
        while (pos <= end) {
          final n = min(512 * 1024, end - pos + 1);
          final chunk = await chatMediaRead(messageId: id, offset: BigInt.from(pos), len: n);
          if (chunk.isEmpty) break;
          res.add(chunk);
          await res.flush();
          pos += chunk.length;
        }
      }
      await res.close();
    } catch (e) {
      // Lecteur qui abandonne une plage (saut dans la vidéo) : normal, rien à signaler.
      if (kDebugMode && e is! SocketException && e is! HttpException) debugPrint('[FOULOVE] vidéo : $e');
      try {
        await res.close();
      } catch (_) {}
    }
  }
}
