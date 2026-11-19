import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../src/rust/api/chat.dart';
import '../../src/rust/api/space.dart';
import '../chat/bubble_look.dart';
import '../chat/chat_service.dart';

/// « Notre espace » : profil du couple, photos, instants, lettres, albums, chiffres.
///
/// Tout passe par le cœur Rust (`core/src/space.rs`) et voyage chiffré par la même boîte d'envoi que les messages ;
/// les fichiers (photo à deux, couverture, fond, instants) prennent le même chemin que les photos de la conversation.
class SpaceService extends ChangeNotifier {
  SpaceService(this.chat);

  final ChatService chat;

  Map<String, String> settings = const {};
  Map<String, SpacePicture> pictures = const {};
  List<Moment> moments = const [];
  List<Letter> letters = const [];
  List<Album> albums = const [];
  SpaceStats? stats;

  Timer? _purge;
  bool _disposed = false;

  String get _partner => chat.partnerId;

  Future<void> load() async {
    await spacePurgeMoments().catchError((_) => 0);
    await Future.wait([_settings(), _pictures(), _moments(), _letters(), _albums(), reloadStats()]);
    // Un instant expire à la minute près, même si rien n'arrive.
    _purge = Timer.periodic(const Duration(minutes: 1), (_) => _expire());
  }

  @override
  void dispose() {
    _disposed = true;
    _purge?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _settings() async {
    settings = {for (final s in await spaceSettings()) s.key: s.value};
  }

  Future<void> _pictures() async {
    pictures = {for (final p in await spacePictures()) p.slot: p};
  }

  Future<void> _moments() async {
    moments = await spaceMoments();
  }

  Future<void> _letters() async {
    letters = await spaceLetters();
  }

  Future<void> _albums() async {
    albums = await spaceAlbums();
  }

  Future<void> reloadStats() async {
    stats = await spaceStats(utcOffsetMin: DateTime.now().timeZoneOffset.inMinutes);
    _notify();
  }

  Future<void> _expire() async {
    final before = moments.length;
    final n = await spacePurgeMoments().catchError((_) => 0);
    await _moments();
    if (n > 0 || moments.length != before) {
      _notify();
      unawaited(chat.transfer()); // les fichiers de nos instants expirés partent de R2
    }
    // Une capsule peut s'ouvrir pendant que l'app est ouverte.
    if (letters.any((l) => l.sealed && (l.openAt ?? 0) <= DateTime.now().millisecondsSinceEpoch)) {
      await _letters();
      _notify();
    }
  }

  /// Appelé par la réception (`ChatService.pull`) quand le partenaire a changé quelque chose.
  Future<void> onReceived(Received r) async {
    if (r.profileChanged) {
      await Future.wait([_settings(), _pictures()]);
      chat.rescheduleReminders();
    }
    if (r.momentsChanged) await _moments();
    if (r.lettersChanged) await _letters();
    if (r.albumsChanged) await _albums();
    if (r.profileChanged || r.momentsChanged || r.lettersChanged || r.albumsChanged) _notify();
  }

  /// Un fichier vient d'être déposé ou téléchargé : s'il s'agit d'une photo du couple ou d'un instant, on rafraîchit.
  Future<void> onFile(String id) async {
    await Future.wait([_pictures(), _moments()]);
    _notify();
  }

  /// Nouvelle activité (message envoyé ou reçu) : la flamme et les chiffres changent peut-être.
  void onActivity() => unawaited(reloadStats());

  // ------------------------------------------------------------------ réglages

  String? get bio => settings['s.bio'];
  String? get storyTitle => settings['s.story_title'];
  String? get story => settings['s.story'];
  String? get myBirthday => settings['me.birthday'];
  String? get partnerBirthday => settings['p.birthday'];
  int get bubbleShape => int.tryParse(settings['s.bubble_shape'] ?? '') ?? 2;
  int? get myColor => int.tryParse(settings['me.bubble_color'] ?? '');
  int? get partnerColor => int.tryParse(settings['p.bubble_color'] ?? '');

  /// Fond de la conversation : un dégradé (index) ou « photo ».
  String get wallpaper => settings['s.wallpaper'] ?? '0';

  int _int(String k, int def) => int.tryParse(settings[k] ?? '') ?? def;

  /// Motif par-dessus le fond (0 aucun) et son intensité (0–100).
  int get pattern => _int('s.pattern', 1);
  int get patternOpacity => _int('s.pattern_opacity', 9);

  /// Votre photo en fond : flou (0–40) et assombrissement (0–100).
  int get photoBlur => _int('s.photo_blur', 12);
  int get photoDim => _int('s.photo_dim', 25);

  /// Bulles : 0 dégradé, 1 uni, 2 verre dépoli, 3 contour.
  int get bubbleStyle => _int('s.bubble_style', 0);

  /// Taille du texte des messages (propre à ce téléphone) : 0 petit, 1 normal, 2 grand.
  int get textSize => _int('me.text_size', 1).clamp(0, 2);

  /// Thème choisi (pour le mettre en évidence) ; -1 si réglé à la main.
  int get theme => _int('s.theme', -1);

  /// Applique un thème complet d'un coup (fond, motif, bulles) ; la couleur des bulles est la tienne.
  Future<void> applyTheme(int i, ChatTheme t) async {
    for (final (k, v, personal) in [
      ('wallpaper', '${t.wallpaper}', false),
      ('pattern', '${t.pattern}', false),
      ('pattern_opacity', '${t.opacity}', false),
      ('bubble_style', '${t.style}', false),
      ('bubble_shape', '${t.shape}', false),
      ('bubble_color', '${t.color}', true),
      ('theme', '$i', false),
    ]) {
      await spaceSetSetting(partner: _partner, key: k, value: v, personal: personal);
    }
    await _settings();
    _notify();
    unawaited(chat.flush());
  }

  /// Réglage choisi à la main : le thème n'est plus « tel quel ».
  Future<void> tweak(String key, String value, {bool personal = false}) async {
    await set(key, value, personal: personal);
    if (theme != -1 && key != 'text_size') await set('theme', '');
  }

  Future<void> set(String key, String value, {bool personal = false}) async {
    await spaceSetSetting(partner: _partner, key: key, value: value, personal: personal);
    await _settings();
    if (key == 'birthday') chat.rescheduleReminders();
    _notify();
    unawaited(chat.flush());
  }

  // ------------------------------------------------------------------ photos du couple

  SpacePicture? get avatar => pictures['avatar'];
  SpacePicture? get cover => pictures['cover'];
  SpacePicture? get wallpaperPhoto => pictures['wallpaper'];

  /// Photo à deux, couverture ou fond : réencodée en JPEG (métadonnées retirées), chiffrée, envoyée.
  Future<void> setPicture(String slot, String path) async {
    final max = slot == 'avatar' ? 1080 : 2048;
    final full = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: max,
      minHeight: max,
      quality: 86,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    // La copie recadrée (ou celle du sélecteur) est en clair dans le cache : effacée dès qu'on a l'image.
    if (path.contains('/cache/')) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    if (full == null) throw StateError('photo illisible');
    final size = await ChatService.imageSize(full);
    final thumb = await ChatService.thumbnail(full);
    final up = await spaceSetPicture(
      dir: chat.mediaDir,
      slot: slot,
      plain: full,
      mime: 'image/jpeg',
      width: size.$1,
      height: size.$2,
      thumb: thumb,
    );
    chat.remember(up.messageId, full);
    await _pictures();
    _notify();
    unawaited(chat.transfer());
  }

  Future<void> removePicture(String slot) async {
    await spaceRemovePicture(partner: _partner, slot: slot);
    await _pictures();
    _notify();
    unawaited(chat.flush());
    unawaited(chat.transfer());
  }

  // ------------------------------------------------------------------ instants

  List<Moment> get mine => moments.where((m) => m.fromMe).toList();
  List<Moment> get theirs => moments.where((m) => !m.fromMe).toList();
  bool get theirsUnseen => theirs.any((m) => !m.seen);

  Future<void> postText(String text, int style) async {
    final p = await spacePostTextMoment(partner: _partner, text: text, style: style);
    moments = [...moments, p.moment];
    _notify();
    unawaited(chat.flush());
  }

  Future<void> postPhoto(String path, {String text = ''}) async {
    final full = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: 1440,
      minHeight: 1440,
      quality: 84,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (full == null) throw StateError('photo illisible');
    final size = await ChatService.imageSize(full);
    final p = await spacePostMediaMoment(
      dir: chat.mediaDir,
      plain: full,
      kind: 1,
      mime: 'image/jpeg',
      width: size.$1,
      height: size.$2,
      durationMs: 0,
      thumb: await ChatService.thumbnail(full),
      text: text,
    );
    chat.remember(p.moment.id, full);
    moments = [...moments, p.moment];
    _notify();
    unawaited(chat.transfer());
  }

  /// Vidéo de 30 s au plus (le sélecteur limite la durée), réencodée et chiffrée par blocs.
  Future<void> postVideo(String path, {String text = '', void Function(double)? onProgress}) async {
    await chat.withCompressedVideo(path, onProgress, (out, thumb, w, h, ms) async {
      final p = await spacePostMediaMoment(
        dir: chat.mediaDir,
        src: out,
        kind: 2,
        mime: 'video/mp4',
        width: w,
        height: h,
        durationMs: ms,
        thumb: thumb,
        text: text,
      );
      moments = [...moments, p.moment];
      _notify();
      unawaited(chat.transfer());
    });
  }

  Future<void> seen(Moment m) async {
    if (m.fromMe || m.seen) return;
    await spaceSeeMoment(partner: _partner, id: m.id);
    await _moments();
    _notify();
    unawaited(chat.flush());
  }

  Future<void> deleteMoment(Moment m) async {
    await spaceDeleteMoment(partner: _partner, id: m.id);
    await _moments();
    _notify();
    unawaited(chat.flush());
    unawaited(chat.transfer());
  }

  Future<void> replyToMoment(Moment m, String text) => chat.replyToMoment(m.id, text);

  // ------------------------------------------------------------------ lettres

  int get unreadLetters => letters.where((l) => !l.fromMe && !l.sealed && l.readAt == null).length;

  Future<void> sendLetter(String title, String body, {DateTime? openAt}) async {
    await spaceSendLetter(partner: _partner, title: title, body: body, openAt: openAt?.millisecondsSinceEpoch);
    await _letters();
    _notify();
    unawaited(chat.flush());
    onActivity();
  }

  Future<void> readLetter(Letter l) async {
    if (l.fromMe || l.sealed || l.readAt != null) return;
    await spaceReadLetter(partner: _partner, id: l.id);
    await _letters();
    _notify();
    unawaited(chat.flush());
  }

  Future<void> starLetter(Letter l, bool on) async {
    await spaceStarLetter(id: l.id, on_: on);
    await _letters();
    _notify();
  }

  // ------------------------------------------------------------------ albums

  Future<Album> saveAlbum({String? id, required String title, required List<String> items}) async {
    final s = await spaceSaveAlbum(partner: _partner, id: id, title: title, items: items);
    await _albums();
    _notify();
    unawaited(chat.flush());
    return s.album;
  }

  Future<void> deleteAlbum(String id) async {
    await spaceDeleteAlbum(partner: _partner, id: id);
    await _albums();
    _notify();
    unawaited(chat.flush());
  }

  // ------------------------------------------------------------------ outils

  /// Photo déchiffrée en mémoire (cache partagé avec la conversation).
  Future<Uint8List?> open(String id) => chat.photo(id);

  /// Vide la corbeille R2 (photos remplacées, instants expirés). Appelé par `ChatService.transfer`.
  static Future<void> emptyTrash(Future<void> Function(String key) delete) async {
    for (final k in await spaceR2Trash()) {
      try {
        await delete(k);
        await spaceR2TrashDone(objectKey: k);
      } on HttpException catch (e) {
        if (kDebugMode) debugPrint('[FOULOVE] corbeille : $e');
      }
    }
  }
}
