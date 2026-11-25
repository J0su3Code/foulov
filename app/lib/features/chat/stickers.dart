import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../../src/rust/api/chat.dart';
import 'chat_service.dart';
import 'sticker_pack.dart';

/// Un sticker prêt à envoyer ou à enregistrer.
typedef PreparedSticker = ({Uint8List bytes, String mime, int width, int height});

/// Bibliothèque de stickers de ce téléphone (base locale chiffrée) : récents, favoris, tous.
///
/// Comme WhatsApp : on enregistre un sticker reçu d'un toucher, on le met en favori, et on importe les siens
/// (photos de la galerie, ou fichiers .webp, par exemple ceux du dossier « WhatsApp Stickers »).
class StickerLibrary extends ChangeNotifier {
  StickerLibrary._();

  static final instance = StickerLibrary._();

  List<Sticker> all = const [];
  bool loaded = false;

  /// Images lues récemment (mémoire seulement), 24 Mo au plus : une grande bibliothèque ne gonfle pas la mémoire.
  final _data = <String, Uint8List>{};
  int _dataBytes = 0;
  static const _dataMax = 24 * 1024 * 1024;

  void _keep(String id, Uint8List b) {
    final old = _data.remove(id);
    if (old != null) _dataBytes -= old.length;
    _data[id] = b;
    _dataBytes += b.length;
    while (_dataBytes > _dataMax && _data.length > 1) {
      _dataBytes -= _data.remove(_data.keys.first)!.length;
    }
  }

  Future<void> load() async {
    try {
      all = await stickerList();
    } catch (_) {
      all = const [];
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (!loaded) await load();
  }

  List<Sticker> get favorites => all.where((s) => s.favorite).toList();

  List<Sticker> get recents {
    final r = all.where((s) => s.usedAt > 0).toList()..sort((a, b) => b.usedAt.compareTo(a.usedAt));
    return r.take(32).toList();
  }

  Sticker? byId(String id) => all.where((s) => s.id == id).firstOrNull;

  /// Image du sticker (gardée en mémoire après la première lecture).
  Future<Uint8List?> data(String id) async {
    final hit = _data[id];
    if (hit != null) {
      _keep(id, hit); // plus récemment utilisée
      return hit;
    }
    final b = await stickerData(id: id);
    if (b != null) _keep(id, b);
    return b;
  }

  /// Enregistre un sticker (reçu, ou importé). Renvoie faux s'il y était déjà.
  Future<({String id, bool added})> add(PreparedSticker s, {bool favorite = false}) async {
    final r = await stickerAdd(data: s.bytes, mime: s.mime, width: s.width, height: s.height);
    _keep(r.id, s.bytes);
    if (favorite) await stickerSetFavorite(id: r.id, favorite: true);
    await load();
    return (id: r.id, added: r.added);
  }

  Future<StickerFound?> find(Uint8List bytes) => stickerFind(data: bytes);

  Future<void> setFavorite(String id, bool on) async {
    await stickerSetFavorite(id: id, favorite: on);
    await load();
  }

  Future<void> remove(String id) async {
    await stickerDelete(id: id);
    final old = _data.remove(id);
    if (old != null) _dataBytes -= old.length;
    await load();
  }

  Future<void> used(String id) async {
    await stickerUsed(id: id);
    await load();
  }

  /// Importe des images de la galerie. Renvoie le nombre de stickers ajoutés.
  Future<int> importFromGallery() async {
    final files = await ImagePicker().pickMultiImage(limit: 30, requestFullMetadata: false);
    return _importAll([for (final f in files) () => f.readAsBytes()]);
  }

  /// Importe des fichiers (.webp, .png, .gif) : par exemple ceux du dossier « WhatsApp/Media/WhatsApp Stickers ».
  Future<int> importFromFiles() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['webp', 'png', 'gif']);
    return _importAll([for (final f in files) () => f.xFile.readAsBytes()]);
  }

  Future<int> _importAll(List<Future<Uint8List> Function()> readers) async {
    var n = 0;
    for (final read in readers) {
      try {
        final s = await prepareSticker(await read());
        final r = await stickerAdd(data: s.bytes, mime: s.mime, width: s.width, height: s.height);
        if (r.added) n++;
      } catch (_) {
        // Image illisible ou trop lourde : on passe à la suivante.
      }
    }
    await load();
    return n;
  }
}

/// Type d'image d'après ses premiers octets.
String? stickerMime(Uint8List b) {
  if (b.length < 12) return null;
  if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42) {
    return 'image/webp';
  }
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
  if (b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
  return null;
}

/// Prépare une image pour en faire un sticker. Un sticker WebP, PNG ou GIF de taille raisonnable est gardé tel quel
/// (il reste animé et transparent) ; le reste est réencodé en WebP de 512 px, sans métadonnées.
Future<PreparedSticker> prepareSticker(Uint8List raw) async {
  final mime = stickerMime(raw);
  if (mime != null && mime != 'image/jpeg' && raw.length <= 1024 * 1024) {
    final (w, h) = await ChatService.imageSize(raw);
    if (w > 0 && h > 0 && w <= 1024 && h <= 1024) return (bytes: raw, mime: mime, width: w, height: h);
  }
  final out = await FlutterImageCompress.compressWithList(
    raw,
    minWidth: 512,
    minHeight: 512,
    quality: 86,
    format: CompressFormat.webp,
    keepExif: false,
  );
  if (out.isEmpty || out.length > 1024 * 1024) throw StateError('sticker trop lourd');
  final (w, h) = await ChatService.imageSize(out);
  return (bytes: out, mime: 'image/webp', width: w, height: h);
}

/// Miniature qui voyage dans le message chiffré (au plus 60 Ko) : le sticker lui-même s'il est léger.
Future<Uint8List> stickerThumb(Uint8List bytes) async {
  if (bytes.length <= 60 * 1024) return bytes;
  for (final q in [70, 45, 25]) {
    final t = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 220,
      minHeight: 220,
      quality: q,
      format: CompressFormat.webp,
    );
    if (t.isNotEmpty && t.length <= 60 * 1024) return t;
  }
  throw StateError('miniature trop lourde');
}

/// Image d'un sticker : transparente, entière (jamais rognée), animée si elle l'est.
class StickerImage extends StatelessWidget {
  const StickerImage(this.bytes, {super.key, this.size});

  final Uint8List bytes;
  final double? size;

  @override
  Widget build(BuildContext context) => Image.memory(
    bytes,
    width: size,
    height: size,
    fit: BoxFit.contain,
    gaplessPlayback: true,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.outline),
  );
}

/// Sticker de la bibliothèque, chargé à la demande.
class LibrarySticker extends StatelessWidget {
  const LibrarySticker(this.sticker, {super.key});

  final Sticker sticker;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: StickerLibrary.instance.data(sticker.id),
    builder: (context, snap) => snap.data == null ? const SizedBox.expand() : StickerImage(snap.data!),
  );
}

// ===================================================================== panneau sous la saisie

/// Panneau des stickers, à la place du clavier (comme WhatsApp) : Récents, Favoris, Mes stickers, et « + ».
class StickerPanel extends StatefulWidget {
  const StickerPanel({super.key, required this.height, required this.onSend, this.bottomInset = 0});

  final double height;

  /// Barre de gestes du système, sous le panneau.
  final double bottomInset;
  final void Function(Sticker sticker, Uint8List bytes) onSend;

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> with SingleTickerProviderStateMixin {
  final _lib = StickerLibrary.instance;
  final _pack = StickerPack.instance;

  /// Onglets : Récents, Favoris, FouLove (le pack), Mes stickers (importés ou enregistrés).
  late final TabController _tabs = TabController(length: 4, vsync: this, initialIndex: _initialTab());

  int _initialTab() {
    if (_lib.recents.isNotEmpty) return 0;
    if (_lib.favorites.isNotEmpty) return 1;
    return 2;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_lib.ensureLoaded());
    unawaited(_pack.ensureLoaded());
  }

  /// Un sticker du pack : téléchargé en entier, rangé dans la bibliothèque (pour Récents et Favoris), puis envoyé.
  Future<Sticker?> _fromPack(PackSticker p) async {
    final b = await _pack.bytes(p.id);
    if (b == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ce sticker n\'a pas pu être téléchargé. Vérifie ta connexion.')));
      }
      return null;
    }
    final r = await _lib.add((bytes: b, mime: 'image/webp', width: p.width, height: p.height));
    return _lib.byId(r.id);
  }

  Future<void> _sendPack(PackSticker p) async {
    final st = await _fromPack(p);
    if (st == null || !mounted) return;
    final b = await _lib.data(st.id);
    if (b != null) widget.onSend(st, b);
  }

  Future<void> _favPack(PackSticker p) async {
    HapticFeedback.mediumImpact();
    final mine = _lib.byId(p.id);
    final messenger = ScaffoldMessenger.of(context);
    if (mine != null) {
      await _lib.setFavorite(mine.id, !mine.favorite);
      messenger.showSnackBar(SnackBar(content: Text(mine.favorite ? 'Retiré des favoris' : 'Ajouté aux favoris ⭐')));
      return;
    }
    final st = await _fromPack(p);
    if (st == null) return;
    await _lib.setFavorite(st.id, true);
    messenger.showSnackBar(const SnackBar(content: Text('Ajouté aux favoris ⭐')));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await importStickers(context);
    if (n == null || !mounted) return;
    if (_tabs.index != 3) _tabs.animateTo(3);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          n == 0
              ? 'Aucun nouveau sticker (déjà enregistrés, ou images illisibles).'
              : n == 1
              ? '1 sticker ajouté'
              : '$n stickers ajoutés',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: widget.height,
      color: cs.surfaceContainer,
      child: ListenableBuilder(
        listenable: Listenable.merge([_lib, _pack]),
        builder: (context, _) => Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabs,
                    dividerHeight: 0,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: cs.primary,
                    unselectedLabelColor: cs.onSurfaceVariant,
                    tabs: const [
                      Tab(icon: Icon(Icons.history_rounded), height: 46),
                      Tab(icon: Icon(Icons.star_rounded), height: 46),
                      Tab(icon: Icon(Icons.favorite_rounded), height: 46),
                      Tab(icon: Icon(Icons.collections_bookmark_outlined), height: 46),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Ajouter des stickers',
                  icon: Icon(Icons.add_circle_outline_rounded, color: cs.primary),
                  onPressed: _import,
                ),
                const SizedBox(width: 4),
              ],
            ),
            Divider(height: 1, color: cs.outline),
            Expanded(
              child: !_lib.loaded
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _grid(_lib.recents, 'Tes stickers envoyés récemment apparaîtront ici.'),
                        _grid(
                          _lib.favorites,
                          'Aucun favori pour l\'instant.\nGarde ton doigt sur un sticker, ou touche un sticker reçu, '
                          'puis « Ajouter aux favoris ».',
                        ),
                        _packGrid(),
                        // Mes stickers : ceux que j'ai importés ou enregistrés (pas ceux du pack déjà envoyés).
                        _grid(_lib.all.where((s) => !_pack.contains(s.id)).toList(), null),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pack FouLove : miniatures chargées à la demande, en grille comme WhatsApp.
  Widget _packGrid() {
    final cs = Theme.of(context).colorScheme;
    if (_pack.items.isEmpty) {
      return Center(
        child: _pack.failed
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Les stickers FouLove n\'ont pas pu être chargés.\nVérifie ta connexion.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(onPressed: () => _pack.load(force: true), child: const Text('Réessayer')),
                  ],
                ),
              )
            : const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + widget.bottomInset),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: _pack.items.length,
      itemBuilder: (context, i) {
        final p = _pack.items[i];
        return InkWell(
          key: ValueKey(p.id),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _sendPack(p),
          onLongPress: () => _favPack(p),
          child: Padding(padding: const EdgeInsets.all(6), child: PackStickerImage(p)),
        );
      },
    );
  }

  Widget _grid(List<Sticker> list, String? empty) {
    final cs = Theme.of(context).colorScheme;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                empty ??
                    'Pas encore de stickers.\nImporte tes images, ou les stickers WhatsApp '
                        '(dossier « WhatsApp Stickers »), ou enregistre ceux que tu reçois.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
              ),
              if (empty == null) ...[
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: _import,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Ajouter des stickers'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + widget.bottomInset),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final s = list[i];
        return InkWell(
          key: ValueKey(s.id),
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final b = await _lib.data(s.id);
            if (b != null) widget.onSend(s, b);
          },
          onLongPress: () => _manage(s),
          child: Padding(padding: const EdgeInsets.all(6), child: LibrarySticker(s)),
        );
      },
    );
  }

  Future<void> _manage(Sticker s) async {
    HapticFeedback.mediumImpact();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 120, width: 120, child: LibrarySticker(s)),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(s.favorite ? Icons.star_outline_rounded : Icons.star_rounded),
              title: Text(s.favorite ? 'Retirer des favoris' : 'Ajouter aux favoris'),
              onTap: () => Navigator.pop(context, 'fav'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
              title: Text('Supprimer de mes stickers', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () => Navigator.pop(context, 'del'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'fav') await _lib.setFavorite(s.id, !s.favorite);
    if (choice == 'del') await _lib.remove(s.id);
  }
}

/// Choix de la source, puis import. `null` : annulé.
Future<int?> importStickers(BuildContext context) async {
  final src = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Depuis la galerie'),
            subtitle: const Text('Tes photos et images (plusieurs à la fois)'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: const Text('Depuis les fichiers'),
            subtitle: const Text(
              'Fichiers .webp, .png ou .gif. Les stickers WhatsApp sont dans '
              'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Stickers',
            ),
            isThreeLine: true,
            onTap: () => Navigator.pop(context, 'files'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (src == null) return null;
  final lib = StickerLibrary.instance;
  try {
    return src == 'gallery' ? await lib.importFromGallery() : await lib.importFromFiles();
  } catch (_) {
    return 0;
  }
}

/// Toucher un sticker reçu (ou envoyé) : le voir en grand, l'enregistrer ou le mettre en favori.
Future<void> showStickerSheet(BuildContext context, ChatService service, ChatMessage m) async {
  final messenger = ScaffoldMessenger.of(context);
  // Le vrai fichier seulement (pas la miniature) : on n'enregistre pas un sticker en basse qualité.
  final bytes = await service.photo(m.id);
  if (!context.mounted) return;
  if (bytes == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Le sticker se télécharge encore. Réessaie dans un instant.')));
    return;
  }
  final lib = StickerLibrary.instance;
  // On cherche sous la forme où il serait enregistré (un sticker trop lourd est réencodé).
  final PreparedSticker prepared;
  try {
    prepared = await prepareSticker(bytes);
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Ce sticker ne peut pas être enregistré.')));
    return;
  }
  final found = await lib.find(prepared.bytes);
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 180, width: 180, child: StickerImage(bytes)),
          const SizedBox(height: 10),
          ListTile(
            leading: Icon(found?.favorite == true ? Icons.star_outline_rounded : Icons.star_rounded),
            title: Text(found?.favorite == true ? 'Retirer des favoris' : 'Ajouter aux favoris'),
            onTap: () => Navigator.pop(context, 'fav'),
          ),
          if (found == null)
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('Enregistrer dans mes stickers'),
              onTap: () => Navigator.pop(context, 'save'),
            )
          else
            ListTile(
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: const Text('Déjà dans tes stickers'),
              enabled: false,
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null) return;
  try {
    if (choice == 'fav' && found != null) {
      await lib.setFavorite(found.id, !found.favorite);
      messenger.showSnackBar(SnackBar(content: Text(found.favorite ? 'Retiré des favoris' : 'Ajouté aux favoris ⭐')));
      return;
    }
    await lib.add(prepared, favorite: choice == 'fav');
    messenger.showSnackBar(
      SnackBar(content: Text(choice == 'fav' ? 'Ajouté aux favoris ⭐' : 'Enregistré dans tes stickers')),
    );
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Ce sticker n\'a pas pu être enregistré.')));
  }
}
