import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../src/rust/api/chat.dart';
import 'chat_service.dart';
import 'video_proxy.dart';

/// Ouvre une photo (visionneuse avec zoom) ou une vidéo (lecteur) en plein écran.
void openMediaViewer(BuildContext context, ChatService service, ChatMessage m) {
  if (m.media!.kind == 2) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VideoViewer(m: m)));
    return;
  }
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, a, _) => FadeTransition(
        opacity: a,
        child: PhotoViewer(m: m, service: service),
      ),
    ),
  );
}

/// Plein écran : la photo occupe tout l'écran (proportions gardées), zoom au pincement jusqu'à ×5,
/// fermeture par glissement vers le bas ou par le bouton.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.m, required this.service});

  final ChatMessage m;
  final ChatService service;

  @override
  State<PhotoViewer> createState() => PhotoViewerState();
}

class PhotoViewerState extends State<PhotoViewer> {
  // Chargée une seule fois : la visionneuse ne redéchiffre pas la photo à chaque reconstruction.
  late final Future<Uint8List?> _photo = widget.service.photo(widget.m.id);

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    Widget fill(Uint8List bytes) => SizedBox.expand(
      child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.medium),
    );
    return Scaffold(
      backgroundColor: Colors.black,
      // expand : sans cela, la pile prend la taille du bouton Fermer, et la photo avec.
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Dismissible(
              key: ValueKey('v-${m.id}'),
              direction: DismissDirection.down,
              onDismissed: (_) => Navigator.of(context).pop(),
              child: InteractiveViewer(
                maxScale: 5,
                child: Hero(
                  tag: 'photo-${m.id}',
                  child: FutureBuilder<Uint8List?>(
                    future: _photo,
                    builder: (context, snap) => fill(snap.data ?? m.media!.thumb),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          if (m.body.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.paddingOf(context).bottom),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Text(m.body, style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
        ],
      ),
    );
  }
}

String formatDuration(int ms) {
  final t = Duration(milliseconds: ms);
  return '${t.inMinutes}:${(t.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// Lecteur plein écran. La vidéo est lue depuis le serveur local qui la déchiffre à la volée :
/// elle n'est jamais écrite en clair sur le téléphone.
class VideoViewer extends StatefulWidget {
  const VideoViewer({super.key, required this.m});

  final ChatMessage m;

  @override
  State<VideoViewer> createState() => VideoViewerState();
}

class VideoViewerState extends State<VideoViewer> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final c = VideoPlayerController.networkUrl(await VideoProxy.url(widget.m.id));
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(() {
        if (mounted) setState(() {});
      });
      setState(() => _c = c);
      await c.play();
      _hideSoon();
    } catch (e) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _hideSoon() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) setState(() => _controls = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _controls = !_controls);
          if (_controls) _hideSoon();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              Center(
                child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
              )
            else
              Center(
                child: _failed
                    ? const Text('Cette vidéo ne peut pas être lue.', style: TextStyle(color: Colors.white))
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.memory(widget.m.media!.thumb, fit: BoxFit.contain),
                          const CircularProgressIndicator(color: Colors.white),
                        ],
                      ),
              ),
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controls,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      child: SafeArea(
                        child: IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          tooltip: 'Fermer',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                    if (ready) ...[
                      Center(
                        child: IconButton(
                          iconSize: 64,
                          icon: Icon(
                            c.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            c.value.isPlaying ? c.pause() : c.play();
                            _hideSoon();
                          },
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16 + MediaQuery.paddingOf(context).bottom,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.m.body.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(widget.m.body, style: const TextStyle(color: Colors.white, fontSize: 16)),
                              ),
                            VideoProgressIndicator(
                              c,
                              allowScrubbing: true,
                              colors: VideoProgressColors(
                                playedColor: Theme.of(context).colorScheme.secondary,
                                bufferedColor: Colors.white38,
                                backgroundColor: Colors.white12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  formatDuration(c.value.position.inMilliseconds),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const Spacer(),
                                Text(
                                  formatDuration(c.value.duration.inMilliseconds),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
