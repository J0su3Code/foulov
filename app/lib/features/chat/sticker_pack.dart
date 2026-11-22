import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Un sticker du pack FouLove.
class PackSticker {
  const PackSticker(this.id, this.width, this.height, this.animated, this.size);

  /// SHA-256 du fichier (le même identifiant que dans la bibliothèque : pas de doublon une fois envoyé).
  final String id;
  final int width, height, size;
  final bool animated;
}

/// Pack de stickers FouLove, hébergé sur Cloudflare R2 : rien dans l'app (qui reste légère), tout se télécharge à la
/// demande puis reste sur le téléphone.
///
/// - L'index (la liste) est relu une fois par jour au plus.
/// - Les miniatures (160 px) se chargent quand elles apparaissent dans la grille ; le sticker entier (animé s'il
///   l'est) au moment de l'envoi.
/// - Les liens de lecture sont signés par la fonction `media`, par lots (le seau reste privé).
/// - Ces fichiers sont communs à tous : ce ne sont pas des données personnelles, ils sont gardés tels quels.
class StickerPack extends ChangeNotifier {
  StickerPack._();

  static final instance = StickerPack._();

  List<PackSticker> items = const [];
  Set<String> _ids = const {};
  bool loading = false;

  /// Chargement impossible (hors ligne) et rien en cache.
  bool failed = false;

  Directory? _dir;
  final _http = http.Client();

  bool contains(String id) => _ids.contains(id);

  Future<Directory> _root() async => _dir ??= await Directory(
    '${(await getApplicationSupportDirectory()).path}/sticker_pack/v1',
  ).create(recursive: true);

  /// Lit l'index en cache, puis le rafraîchit s'il a plus d'un jour (ou s'il manque).
  Future<void> load({bool force = false}) async {
    if (loading) return;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final dir = await _root();
      final cached = File('${dir.path}/index.json');
      if (cached.existsSync()) _parse(await cached.readAsString());
      final stale = !cached.existsSync() || DateTime.now().difference(cached.lastModifiedSync()).inHours >= 24;
      if (force || stale || items.isEmpty) {
        try {
          final bytes = await _download('v1/index.json');
          _parse(utf8.decode(bytes));
          await cached.writeAsBytes(bytes, flush: true);
        } catch (e) {
          if (kDebugMode) debugPrint('[FOULOVE] index des stickers : $e');
          if (items.isEmpty) failed = true;
        }
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> ensureLoaded() async {
    if (items.isEmpty && !loading) await load();
  }

  void _parse(String json) {
    final list = (jsonDecode(json) as Map<String, dynamic>)['stickers'] as List<dynamic>;
    items = [
      for (final m in list.cast<Map<String, dynamic>>())
        PackSticker(m['id'] as String, m['w'] as int, m['h'] as int, m['a'] == 1, m['s'] as int),
    ];
    _ids = {for (final s in items) s.id};
  }

  // ------------------------------------------------------------------ fichiers

  final _pending = <String, Completer<File?>>{};
  Timer? _batch;

  /// Fichier du sticker (`thumb` : miniature) sur le téléphone, téléchargé s'il le faut.
  Future<File?> file(String id, {bool thumb = false}) async {
    final dir = await _root();
    final key = thumb ? 'v1/t/$id.webp' : 'v1/$id.webp';
    final f = File(thumb ? '${dir.path}/t/$id.webp' : '${dir.path}/$id.webp');
    if (f.existsSync()) return f;
    final c = _pending[key];
    if (c != null) return c.future;
    final done = Completer<File?>();
    _pending[key] = done;
    // Les demandes d'une même image de la grille partent ensemble : un seul appel pour signer tous les liens.
    _batch ??= Timer(const Duration(milliseconds: 60), _flush);
    return done.future;
  }

  Future<Uint8List?> bytes(String id) async {
    final f = await file(id);
    return f?.readAsBytes();
  }

  Future<void> _flush() async {
    _batch = null;
    final keys = _pending.keys.take(120).toList();
    if (_pending.length > keys.length) _batch = Timer(const Duration(milliseconds: 10), _flush);
    final waiting = {for (final k in keys) k: _pending.remove(k)!};
    Map<String, String> urls;
    try {
      urls = await _sign(keys);
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] liens des stickers : $e');
      for (final c in waiting.values) {
        c.complete(null);
      }
      return;
    }
    final dir = await _root();
    // Quatre téléchargements à la fois : rapide, sans saturer une connexion mobile.
    final queue = keys.toList();
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final k = queue.removeLast();
        final rel = k.substring(3); // « t/<id>.webp » ou « <id>.webp »
        final f = File('${dir.path}/$rel');
        try {
          final url = urls[k];
          if (url == null) throw StateError('lien manquant');
          final r = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
          if (r.statusCode != 200 || r.bodyBytes.isEmpty) throw HttpException('sticker ${r.statusCode}');
          await f.parent.create(recursive: true);
          final tmp = File('${f.path}.part');
          await tmp.writeAsBytes(r.bodyBytes, flush: true);
          await tmp.rename(f.path);
          waiting[k]!.complete(f);
        } catch (e) {
          if (kDebugMode) debugPrint('[FOULOVE] sticker $k : $e');
          waiting[k]!.complete(null);
        }
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
  }

  Future<Map<String, String>> _sign(List<String> keys) async {
    final r = await Supabase.instance.client.functions
        .invoke('media', body: {'action': 'stickers', 'keys': keys})
        .timeout(const Duration(seconds: 30));
    if (r.status != 200 || r.data is! Map) throw HttpException('lien ${r.status}');
    return Map<String, String>.from((r.data as Map)['urls'] as Map);
  }

  Future<Uint8List> _download(String key) async {
    final urls = await _sign([key]);
    final r = await _http.get(Uri.parse(urls[key]!)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw HttpException('index ${r.statusCode}');
    return r.bodyBytes;
  }
}

/// Sticker du pack, affiché dès que son fichier est sur le téléphone.
class PackStickerImage extends StatefulWidget {
  const PackStickerImage(this.sticker, {super.key, this.thumb = true});

  final PackSticker sticker;
  final bool thumb;

  @override
  State<PackStickerImage> createState() => _PackStickerImageState();
}

class _PackStickerImageState extends State<PackStickerImage> {
  late Future<File?> _file = StickerPack.instance.file(widget.sticker.id, thumb: widget.thumb);

  @override
  void didUpdateWidget(PackStickerImage old) {
    super.didUpdateWidget(old);
    if (old.sticker.id != widget.sticker.id || old.thumb != widget.thumb) {
      _file = StickerPack.instance.file(widget.sticker.id, thumb: widget.thumb);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (context, snap) {
      final f = snap.data;
      if (f == null) {
        return snap.connectionState == ConnectionState.done
            ? Icon(Icons.cloud_off_rounded, size: 18, color: Theme.of(context).colorScheme.outline)
            : const SizedBox.expand();
      }
      return Image.file(
        f,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        cacheWidth: widget.thumb ? 200 : null,
      );
    },
  );
}
