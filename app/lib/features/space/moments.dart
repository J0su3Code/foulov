import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../src/rust/api/space.dart';
import '../../theme/foulov_theme.dart';
import '../chat/video_proxy.dart';
import 'space_service.dart';
import 'widgets.dart';

/// Ouvre les instants de l'un de vous deux (les siens, ou les tiens), en commençant par le premier non vu.
Future<void> openMoments(BuildContext context, SpaceService space, {required bool mine}) async {
  final list = mine ? space.mine : space.theirs;
  if (list.isEmpty) return;
  final start = mine ? 0 : list.indexWhere((m) => !m.seen).clamp(0, list.length - 1);
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, a, _) => FadeTransition(
        opacity: a,
        child: MomentViewer(space: space, moments: list, start: start),
      ),
    ),
  );
}

/// Propose de publier un instant : écrire, choisir une photo ou une vidéo, ou en prendre une.
Future<void> composeMoment(BuildContext context, SpaceService space) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Text(
              'Un instant, visible 24 h, rien que par vous deux.',
              style: TextStyle(color: context.cs.onSurfaceVariant),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.text_fields_rounded),
            title: const Text('Écrire un mot'),
            onTap: () => Navigator.pop(context, 'text'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Photo ou vidéo de la galerie'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Filmer (30 s)'),
            onTap: () => Navigator.pop(context, 'film'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'text') {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _TextMoment(space: space)));
    return;
  }
  final picker = ImagePicker();
  XFile? f;
  var video = false;
  try {
    switch (choice) {
      case 'gallery':
        f = await picker.pickMedia(requestFullMetadata: false);
        video = f != null && _isVideo(f.path);
      case 'camera':
        f = await picker.pickImage(source: ImageSource.camera, requestFullMetadata: false);
      case 'film':
        f = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 30));
        video = true;
    }
  } on PlatformException {
    if (context.mounted) _snack(context, 'Accès refusé. Autorise FouLove dans les réglages du téléphone.');
    return;
  }
  if (f == null || !context.mounted) return;
  if (video) {
    final c = VideoPlayerController.file(File(f.path));
    try {
      await c.initialize();
      if (c.value.duration > const Duration(seconds: 31)) {
        if (context.mounted) _snack(context, 'Un instant vidéo dure 30 secondes au plus.');
        return;
      }
    } catch (_) {
      if (context.mounted) _snack(context, 'Cette vidéo n\'a pas pu être lue.');
      return;
    } finally {
      await c.dispose();
    }
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _MediaMoment(space: space, path: f!.path, video: video),
    ),
  );
}

bool _isVideo(String p) {
  final l = p.toLowerCase();
  return l.endsWith('.mp4') || l.endsWith('.mov') || l.endsWith('.3gp') || l.endsWith('.mkv') || l.endsWith('.webm');
}

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

// ===================================================================== création : texte

class _TextMoment extends StatefulWidget {
  const _TextMoment({required this.space});

  final SpaceService space;

  @override
  State<_TextMoment> createState() => _TextMomentState();
}

class _TextMomentState extends State<_TextMoment> {
  final _text = TextEditingController();
  int _style = 0;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_text.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.space.postText(_text.text, _style);
      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(context, 'Cet instant n\'a pas pu être préparé. Réessaie.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: MomentStyles.of(_style),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Fermer',
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        minimumSize: const Size(64, 42),
                      ),
                      onPressed: _text.text.trim().isEmpty || _busy ? null : _post,
                      child: Text(_busy ? 'Envoi…' : 'Partager'),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: TextField(
                      controller: _text,
                      autofocus: true,
                      maxLines: null,
                      maxLength: 500,
                      textAlign: TextAlign.center,
                      onChanged: (_) => setState(() {}),
                      cursorColor: Colors.white,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                      decoration: const InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        counterText: '',
                        hintText: 'Un mot doux…',
                        hintStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 64,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  children: [
                    for (var i = 0; i < MomentStyles.all.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () => setState(() => _style = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: MomentStyles.of(i)),
                              border: Border.all(color: Colors.white, width: i == _style ? 3 : 1.2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================================================================== création : photo ou vidéo

class _MediaMoment extends StatefulWidget {
  const _MediaMoment({required this.space, required this.path, required this.video});

  final SpaceService space;
  final String path;
  final bool video;

  @override
  State<_MediaMoment> createState() => _MediaMomentState();
}

class _MediaMomentState extends State<_MediaMoment> {
  final _text = TextEditingController();
  VideoPlayerController? _player;
  bool _busy = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    if (widget.video) {
      final c = VideoPlayerController.file(File(widget.path));
      _player = c;
      c.initialize().then((_) {
        if (!mounted) return;
        c.setLooping(true);
        c.play();
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    setState(() => _busy = true);
    await _player?.pause();
    try {
      if (widget.video) {
        await widget.space.postVideo(
          widget.path,
          text: _text.text,
          onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        );
      } else {
        await widget.space.postPhoto(widget.path, text: _text.text);
      }
      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(context, 'Cet instant n\'a pas pu être préparé. Réessaie.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!widget.video)
            Image.file(File(widget.path), fit: BoxFit.contain)
          else if (p != null && p.value.isInitialized)
            Center(
              child: AspectRatio(aspectRatio: p.value.aspectRatio, child: VideoPlayer(p)),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      tooltip: 'Fermer',
                    ),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _text,
                          maxLength: 500,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'Ajouter un mot…',
                            hintStyle: const TextStyle(color: Colors.white70),
                            fillColor: Colors.black38,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: const BorderSide(color: Colors.white54),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: const BorderSide(color: Colors.white54),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(64, 50)),
                        onPressed: _busy ? null : _post,
                        child: Text(_busy ? (widget.video ? '${(_progress * 100).round()} %' : 'Envoi…') : 'Partager'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===================================================================== lecture

/// Plein écran : barres de progression, toucher à droite / à gauche pour passer, appui long pour mettre en pause,
/// glisser vers le bas pour fermer. Les siens : répondre ou envoyer un cœur. Les tiens : vu ou non, retirer.
class MomentViewer extends StatefulWidget {
  const MomentViewer({super.key, required this.space, required this.moments, this.start = 0});

  final SpaceService space;
  final List<Moment> moments;
  final int start;

  @override
  State<MomentViewer> createState() => _MomentViewerState();
}

class _MomentViewerState extends State<MomentViewer> with SingleTickerProviderStateMixin {
  late int _i = widget.start;
  late final AnimationController _clock = AnimationController(vsync: this)..addStatusListener(_onEnd);
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  VideoPlayerController? _video;
  bool _held = false;
  double _drag = 0;

  Moment get _m => widget.moments[_i];

  @override
  void initState() {
    super.initState();
    widget.space.addListener(_changed);
    _replyFocus.addListener(() => _replyFocus.hasFocus ? _clock.stop() : _resume());
    _show();
  }

  @override
  void dispose() {
    widget.space.removeListener(_changed);
    _clock.dispose();
    _video?.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  /// Le fichier vient d'arriver (téléchargé pendant l'affichage) : on relance l'affichage de cet instant.
  void _changed() {
    final fresh = widget.space.moments.where((x) => x.id == _m.id).firstOrNull;
    if (fresh == null) {
      // Retiré par son auteur, ou expiré.
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    if (fresh.media?.state != _m.media?.state) {
      widget.moments[_i] = fresh;
      _show();
    }
  }

  Future<void> _show() async {
    final m = _m;
    _clock.stop();
    _clock.value = 0;
    await _video?.dispose();
    _video = null;
    if (!m.fromMe) unawaited(widget.space.seen(m));
    final ready = m.media == null || m.media!.state == 1 || (m.fromMe && m.media!.state == 0);
    if (m.kind == 2 && ready) {
      try {
        final c = VideoPlayerController.networkUrl(await VideoProxy.url(m.id));
        await c.initialize();
        if (!mounted || _m.id != m.id) {
          await c.dispose();
          return;
        }
        _video = c;
        _clock.duration = c.value.duration > Duration.zero ? c.value.duration : const Duration(seconds: 10);
        await c.play();
      } catch (_) {
        _clock.duration = const Duration(seconds: 5);
      }
    } else {
      // Texte : selon sa longueur ; photo : 6 s.
      _clock.duration = Duration(milliseconds: m.kind == 4 ? (4000 + m.text.length * 40).clamp(5000, 12000) : 6000);
    }
    if (!mounted) return;
    setState(() {});
    if (ready) _resume();
  }

  void _resume() {
    if (_held || _replyFocus.hasFocus || !mounted) return;
    _clock.forward();
    _video?.play();
  }

  void _pause() {
    _clock.stop();
    _video?.pause();
  }

  void _onEnd(AnimationStatus s) {
    if (s == AnimationStatus.completed) _next();
  }

  void _next() {
    if (_i < widget.moments.length - 1) {
      setState(() => _i++);
      _show();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_i > 0) {
      setState(() => _i--);
      _show();
    } else {
      _show();
    }
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    final m = _m;
    _reply.clear();
    _replyFocus.unfocus();
    HapticFeedback.lightImpact();
    try {
      await widget.space.replyToMoment(m, text);
      if (mounted) _snack(context, 'Envoyé dans votre conversation ♡');
    } catch (_) {
      if (mounted) _snack(context, 'La réponse n\'a pas pu partir. Réessaie.');
    }
  }

  Future<void> _delete() async {
    _pause();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer cet instant ?'),
        content: const Text('Il disparaîtra aussi de son téléphone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok == true) {
      await widget.space.deleteMoment(_m);
      if (mounted) Navigator.of(context).maybePop();
    } else {
      _resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    final name = m.fromMe ? 'Toi' : widget.space.chat.partnerLabel;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(0, 400)),
        onVerticalDragEnd: (d) {
          if (_drag > 120 || d.velocity.pixelsPerSecond.dy > 900) {
            Navigator.of(context).maybePop();
          } else {
            setState(() => _drag = 0);
          }
        },
        onLongPressStart: (_) {
          _held = true;
          _pause();
        },
        onLongPressEnd: (_) {
          _held = false;
          _resume();
        },
        onTapUp: (d) {
          if (_replyFocus.hasFocus) {
            _replyFocus.unfocus();
            return;
          }
          d.localPosition.dx < MediaQuery.sizeOf(context).width / 3 ? _prev() : _next();
        },
        child: Transform.translate(
          offset: Offset(0, _drag),
          child: Opacity(
            opacity: (1 - _drag / 600).clamp(.4, 1),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Content(space: widget.space, m: m, video: _video),
                // Voiles pour garder lisibles le haut et le bas.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x73000000), Color(0x00000000), Color(0x00000000), Color(0x8C000000)],
                      stops: [0, .22, .7, 1],
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                        child: Row(
                          children: [
                            for (var k = 0; k < widget.moments.length; k++)
                              Expanded(
                                child: Container(
                                  height: 2.6,
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .35),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: k < _i
                                      ? Container(color: Colors.white)
                                      : k == _i
                                      ? AnimatedBuilder(
                                          animation: _clock,
                                          builder: (_, _) => FractionallySizedBox(
                                            widthFactor: _clock.value,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                        child: Row(
                          children: [
                            CoupleAvatar(space: widget.space, size: 32),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: name,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    TextSpan(
                                      text: '  ${ago(m.createdAt)}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                                    ),
                                  ],
                                ),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            if (m.fromMe)
                              IconButton(
                                onPressed: _delete,
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                                tooltip: 'Retirer',
                              ),
                            IconButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.close_rounded, color: Colors.white),
                              tooltip: 'Fermer',
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (m.kind != 4 && m.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                          child: Text(
                            m.text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              shadows: [Shadow(blurRadius: 14, color: Colors.black54)],
                            ),
                          ),
                        ),
                      if (m.fromMe)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                m.seen ? Icons.visibility_rounded : Icons.visibility_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                m.seen ? 'Vu par ${widget.space.chat.partnerLabel}' : 'Pas encore vu',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 8, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _reply,
                                  focusNode: _replyFocus,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: _send,
                                  style: const TextStyle(color: Colors.white),
                                  cursorColor: Colors.white,
                                  decoration: InputDecoration(
                                    hintText: 'Répondre à ${widget.space.chat.partnerLabel}…',
                                    hintStyle: const TextStyle(color: Colors.white70),
                                    fillColor: Colors.transparent,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(28),
                                      borderSide: const BorderSide(color: Colors.white60),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(28),
                                      borderSide: const BorderSide(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _send(_reply.text.trim().isEmpty ? '❤️' : _reply.text),
                                icon: Icon(
                                  _reply.text.trim().isEmpty ? Icons.favorite_rounded : Icons.send_rounded,
                                  color: _reply.text.trim().isEmpty ? const Color(0xFFFF6F9F) : Colors.white,
                                  size: 30,
                                ),
                                tooltip: 'Envoyer',
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.space, required this.m, required this.video});

  final SpaceService space;
  final Moment m;
  final VideoPlayerController? video;

  @override
  Widget build(BuildContext context) {
    if (m.kind == 4) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: MomentStyles.of(m.style),
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              m.text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, height: 1.25),
            ),
          ),
        ),
      );
    }
    final md = m.media!;
    final ready = md.state == 1 || (m.fromMe && md.state == 0);
    final v = video;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fond flou (la miniature), pour les photos qui ne remplissent pas l'écran.
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Image.memory(md.thumb, fit: BoxFit.cover, gaplessPlayback: true),
        ),
        if (m.kind == 2 && v != null && v.value.isInitialized)
          Center(
            child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)),
          )
        else if (m.kind == 1)
          SecureImage(
            key: ValueKey('${m.id}-${md.state}'),
            space: space,
            id: m.id,
            thumb: md.thumb,
            fit: BoxFit.contain,
          ),
        if (!ready || (m.kind == 2 && v == null)) const Center(child: CircularProgressIndicator(color: Colors.white)),
      ],
    );
  }
}
