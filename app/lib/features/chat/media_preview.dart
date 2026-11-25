import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart' as vc;

/// Un élément choisi dans la galerie, prêt à partir.
typedef PickedMedia = ({XFile file, bool video});

/// Au plus 30 photos ou vidéos à la fois.
const maxPicked = 30;

bool isVideoFile(XFile f) {
  final t = f.mimeType;
  if (t != null) return t.startsWith('video/');
  final p = f.path.toLowerCase();
  return ['.mp4', '.mov', '.3gp', '.webm', '.mkv'].any(p.endsWith);
}

/// Aperçu avant l'envoi, comme WhatsApp : les photos en grand, la bande des miniatures (toucher pour voir, croix pour
/// retirer, « + » pour en ajouter), une légende, le bouton « 1 » (vue unique, pour un seul élément), puis Envoyer.
/// Renvoie la sélection, la légende et le choix « vue unique », ou `null`.
Future<(List<PickedMedia>, String, bool)?> previewMedia(
  BuildContext context,
  List<XFile> files, {
  String caption = '',
  required String to,
}) => Navigator.of(context).push<(List<PickedMedia>, String, bool)>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) =>
        _MediaPreview(initial: [for (final f in files) (file: f, video: isVideoFile(f))], caption: caption, to: to),
  ),
);

class _MediaPreview extends StatefulWidget {
  const _MediaPreview({required this.initial, required this.caption, required this.to});

  final List<PickedMedia> initial;
  final String caption;
  final String to;

  @override
  State<_MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<_MediaPreview> {
  late final List<PickedMedia> _items = [...widget.initial];
  late final _caption = TextEditingController(text: widget.caption);

  /// Vue unique (bouton « 1 ») : seulement quand un seul élément part.
  bool _once = false;
  final _pages = PageController();
  int _current = 0;

  @override
  void dispose() {
    _caption.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _show(int i) {
    setState(() => _current = i);
    _pages.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  void _remove(int i) {
    HapticFeedback.selectionClick();
    setState(() {
      _items.removeAt(i);
      if (_current >= _items.length) _current = _items.length - 1;
    });
    if (_items.isEmpty) {
      Navigator.pop(context);
      return;
    }
    _pages.jumpToPage(_current);
  }

  Future<void> _addMore() async {
    final left = maxPicked - _items.length;
    if (left <= 0) return;
    final picker = ImagePicker();
    final List<XFile> more;
    try {
      // Une seule place : le sélecteur multiple refuse une limite de 1.
      more = left == 1
          ? [?await picker.pickMedia(requestFullMetadata: false)]
          : await picker.pickMultipleMedia(limit: left, requestFullMetadata: false);
    } catch (_) {
      return;
    }
    if (more.isEmpty || !mounted) return;
    setState(() => _items.addAll([for (final f in more.take(left)) (file: f, video: isVideoFile(f))]));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: cs.copyWith(surface: Colors.black, onSurface: Colors.white),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          systemOverlayStyle: SystemUiOverlayStyle.light,
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
          title: Text(
            _items.length == 1 ? '1 élément' : '${_items.length} éléments',
            style: const TextStyle(color: Colors.white, fontSize: 17),
          ),
          actions: [
            IconButton(
              tooltip: 'Retirer celui-ci',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _remove(_current),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _items.length,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (context, i) => _items[i].video
                    ? _VideoFrame(key: ValueKey(_items[i].file.path), path: _items[i].file.path)
                    : InteractiveViewer(
                        maxScale: 4,
                        child: Center(child: Image.file(File(_items[i].file.path), fit: BoxFit.contain)),
                      ),
              ),
            ),
            // Bande des miniatures.
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _items.length + (_items.length < maxPicked ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  if (i == _items.length) {
                    return InkWell(
                      onTap: _addMore,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white38),
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white),
                      ),
                    );
                  }
                  final sel = i == _current;
                  return GestureDetector(
                    onTap: () => _show(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: sel ? cs.primary : Colors.transparent, width: 2.5),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _items[i].video
                                ? _VideoFrame(
                                    key: ValueKey('s-${_items[i].file.path}'),
                                    path: _items[i].file.path,
                                    small: true,
                                  )
                                : Image.file(File(_items[i].file.path), fit: BoxFit.cover, cacheWidth: 160),
                            if (_items[i].video)
                              const Positioned(
                                left: 3,
                                bottom: 2,
                                child: Icon(Icons.videocam_rounded, color: Colors.white, size: 15),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Légende et envoi.
            Padding(
              padding: EdgeInsets.fromLTRB(10, 4, 10, 10 + bottom + MediaQuery.viewInsetsOf(context).bottom),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(24)),
                      child: TextField(
                        controller: _caption,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        cursorColor: cs.primary,
                        decoration: const InputDecoration(
                          hintText: 'Ajouter une légende…',
                          hintStyle: TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  if (_items.length == 1) ...[
                    const SizedBox(width: 6),
                    _OnceButton(
                      on: _once,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _once = !_once);
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                              content: Text(
                                _once
                                    ? 'Vue unique : ${widget.to} pourra l\'ouvrir une seule fois, sans capture d\'écran.'
                                    : 'Vue unique désactivée.',
                              ),
                            ),
                          );
                      },
                    ),
                  ],
                  const SizedBox(width: 8),
                  Material(
                    color: cs.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.pop(
                        context,
                        (List<PickedMedia>.of(_items), _caption.text.trim(), _once && _items.length == 1),
                      ),
                      child: SizedBox.square(
                        dimension: 50,
                        child: Icon(Icons.send_rounded, color: cs.onPrimary, semanticLabel: 'Envoyer'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Première image d'une vidéo (calculée sur le téléphone).
class _VideoFrame extends StatefulWidget {
  const _VideoFrame({super.key, required this.path, this.small = false});

  final String path;
  final bool small;

  @override
  State<_VideoFrame> createState() => _VideoFrameState();
}

class _VideoFrameState extends State<_VideoFrame> {
  late final Future<Uint8List?> _frame = vc.VideoCompress.getByteThumbnail(
    widget.path,
    quality: 60,
  ).catchError((_) => null);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _frame,
    builder: (context, snap) {
      final b = snap.data;
      if (widget.small) {
        return b == null ? const ColoredBox(color: Colors.white10) : Image.memory(b, fit: BoxFit.cover);
      }
      return Stack(
        alignment: Alignment.center,
        children: [
          if (b != null) Image.memory(b, fit: BoxFit.contain),
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
          ),
        ],
      );
    },
  );
}

/// Le bouton « 1 » de la vue unique, comme sur WhatsApp : un chiffre dans un cercle, plein quand il est actif.
class _OnceButton extends StatelessWidget {
  const _OnceButton({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      toggled: on,
      label: 'Vue unique',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 40,
          margin: const EdgeInsets.only(bottom: 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? cs.primary : Colors.transparent,
            border: Border.all(color: on ? cs.primary : Colors.white70, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            '1',
            style: TextStyle(color: on ? cs.onPrimary : Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
