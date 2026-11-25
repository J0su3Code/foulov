import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../src/rust/api/chat.dart';
import 'chat_service.dart';
import 'video_proxy.dart';

/// Vue unique (comme WhatsApp) : la photo ou la vidéo s'ouvre une fois, en plein écran, **sans capture d'écran
/// possible** (ni aperçu dans les apps récentes, Android). En la refermant, ou si l'app passe en arrière-plan, elle
/// est détruite sur ce téléphone et sur le serveur, et l'expéditeur voit « Ouverte ».
///
/// Limite dite honnêtement : rien n'empêche de la photographier avec un autre appareil.
Future<void> openViewOnce(BuildContext context, ChatService service, ChatMessage m) async {
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  try {
    await service.openViewOnce(m.id);
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Cette vue unique a déjà été ouverte.')));
    return;
  }
  await _secure(true);
  try {
    await nav.push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, a, _) => FadeTransition(opacity: a, child: _ViewOnceScreen(m: m)),
      ),
    );
  } finally {
    await _secure(false);
    await service.closeViewOnce(m.id);
  }
}

Future<void> _secure(bool on) async {
  try {
    await const MethodChannel('foulove/notifications').invokeMethod<void>('secure', on);
  } catch (_) {}
}

class _ViewOnceScreen extends StatefulWidget {
  const _ViewOnceScreen({required this.m});

  final ChatMessage m;

  @override
  State<_ViewOnceScreen> createState() => _ViewOnceScreenState();
}

class _ViewOnceScreenState extends State<_ViewOnceScreen> with WidgetsBindingObserver {
  Uint8List? _photo;
  VideoPlayerController? _video;
  bool _failed = false;
  bool get _isVideo => widget.m.media?.kind == 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      if (_isVideo) {
        final c = VideoPlayerController.networkUrl(await VideoProxy.url(widget.m.id));
        await c.initialize();
        if (!mounted) return c.dispose();
        c.addListener(() {
          if (!mounted) return;
          setState(() {});
          // Fin de la vidéo : elle ne se rejoue pas.
          final v = c.value;
          if (v.isInitialized && !v.isPlaying && v.position >= v.duration && v.duration > Duration.zero) _close();
        });
        setState(() => _video = c);
        await c.play();
      } else {
        final b = await chatOpenMedia(messageId: widget.m.id);
        if (mounted) setState(() => _photo = b);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  // Comme WhatsApp : quitter l'app pendant l'affichage referme (et consomme) la vue unique.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _close();
  }

  bool _closed = false;
  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _video?.dispose();
    _photo = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: _failed
                  ? const Text('Cette vue unique ne peut pas être ouverte.', style: TextStyle(color: Colors.white))
                  : _photo != null
                  ? InteractiveViewer(maxScale: 4, child: Image.memory(_photo!, fit: BoxFit.contain))
                  : v != null && v.value.isInitialized
                  ? AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v))
                  : const CircularProgressIndicator(color: Colors.white),
            ),
            Positioned(
              top: 6,
              left: 6,
              right: 6,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Fermer',
                    onPressed: _close,
                  ),
                  const _OnceBadge(),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Vue unique',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            if (v != null && v.value.isInitialized)
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: VideoProgressIndicator(v, allowScrubbing: false, colors: VideoProgressColors(playedColor: Colors.white)),
              ),
            if (widget.m.body.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 34,
                child: Text(
                  widget.m.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15, shadows: [Shadow(blurRadius: 6)]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Le petit « 1 » dans un cercle.
class _OnceBadge extends StatelessWidget {
  const _OnceBadge({this.color = Colors.white});

  static const size = 22.0;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 1.8)),
    child: Text('1', style: TextStyle(color: color, fontSize: size * .55, fontWeight: FontWeight.w800, height: 1)),
  );
}

/// Bulle d'une vue unique, comme WhatsApp : pas d'image, juste « ① Photo » / « Vidéo », puis « Ouverte » ou « Expirée ».
class ViewOnceBubble extends StatelessWidget {
  const ViewOnceBubble({
    super.key,
    required this.m,
    required this.mine,
    required this.fg,
    required this.decoration,
    required this.meta,
    this.quote,
  });

  final ChatMessage m;
  final bool mine;
  final Color fg;
  final Decoration decoration;
  final Widget meta;
  final Widget? quote;

  @override
  Widget build(BuildContext context) {
    final md = m.media!;
    final video = md.kind == 2;
    final what = video ? 'Vidéo' : 'Photo';
    final (label, active) = switch (md.viewOnce) {
      2 => ('Ouverte', false),
      4 => ('Expirée', false),
      _ when mine => (what, false),
      _ when md.state == 2 => ('$what · téléchargement…', false),
      _ when md.state == 3 => ('$what illisible', false),
      _ => (what, true),
    };
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .7),
      padding: EdgeInsets.fromLTRB(quote == null ? 12 : 4, quote == null ? 9 : 4, quote == null ? 12 : 4, 7),
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ?quote,
          Padding(
            padding: EdgeInsets.symmetric(horizontal: quote == null ? 0 : 8, vertical: quote == null ? 0 : 4),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                _OnceBadge(color: active ? fg : fg.withValues(alpha: .6)),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? fg : fg.withValues(alpha: .7),
                    fontSize: 15,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    fontStyle: active ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
                meta,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
