import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../theme/foulov_theme.dart';

/// Intro cinématique de la première ouverture.
///
/// Synchronisation, sans aucun saut visible :
/// 1. Le splash natif affiche une couleur unie ([FouLovColors.splashDay] ou [FouLovColors.splashNight]).
/// 2. Ce widget affiche la même couleur tant que la vidéo n'est pas prête.
/// 3. La vidéo commence par un fondu depuis cette couleur (voir animation/export_app_assets.sh).
/// 4. À la fin, la dernière image (exportée à l'identique) reste en fond et le panneau d'accueil monte.
///
/// Toucher l'écran pendant la vidéo passe directement à la fin. Si le système demande de réduire
/// les animations, on affiche directement l'état final.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onStart, required this.onJoin});

  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  VideoPlayerController? _video;
  bool _night = false;
  bool _ready = false;
  bool _finished = false;

  String get _name => _night ? 'intro_night' : 'intro_day';
  Color get _splash => _night ? FouLovColors.splashNight : FouLovColors.splashDay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_video != null || _finished) return;
    _night = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    // Précharge la dernière image pour qu'elle soit décodée avant la fin de la vidéo.
    precacheImage(AssetImage('assets/intro/${_name}_last.jpg'), context);
    if (MediaQuery.disableAnimationsOf(context)) {
      _finished = true;
      return;
    }
    _start();
  }

  Future<void> _start() async {
    final c = VideoPlayerController.asset(
      'assets/intro/$_name.mp4',
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _video = c;
    try {
      await c.initialize();
      await c.setVolume(0);
      c.addListener(_onTick);
      if (!mounted) return;
      setState(() => _ready = true);
      await c.play();
    } catch (_) {
      // Lecteur indisponible : on montre l'état final plutôt qu'un écran vide.
      if (mounted) setState(() => _finished = true);
    }
  }

  void _onTick() {
    final c = _video;
    if (c == null || _finished) return;
    final v = c.value;
    if (v.isInitialized && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 40)) {
      setState(() => _finished = true);
    }
  }

  void _skip() {
    if (_finished) return;
    HapticFeedback.selectionClick();
    _video?.pause();
    setState(() => _finished = true);
  }

  @override
  void dispose() {
    _video?.removeListener(_onTick);
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _night ? FouLovTheme.nuit : FouLovTheme.jour;
    final c = _video;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Theme(
        data: theme,
        child: Scaffold(
          backgroundColor: _splash,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _skip,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Dernière image : visible dès que la vidéo se termine (ou si elle est sautée).
                if (_finished) Image.asset('assets/intro/${_name}_last.jpg', fit: BoxFit.cover, gaplessPlayback: true),
                if (!_finished && _ready && c != null)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
                  ),
                _WelcomeSheet(visible: _finished, onStart: widget.onStart, onJoin: widget.onJoin),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeSheet extends StatelessWidget {
  const _WelcomeSheet({required this.visible, required this.onStart, required this.onJoin});

  final bool visible;
  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.05),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: Material(
            color: t.colorScheme.surface,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 28, 24, 20 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rien que\nvous deux.',
                    style: t.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: t.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Votre bulle privée : vos mots, vos photos, vos souvenirs. Chiffrés, pour toujours entre vous.',
                    style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: visible ? onStart : null, child: const Text('Commencer')),
                  ),
                  const SizedBox(height: 6),
                  TextButton(onPressed: visible ? onJoin : null, child: const Text("J'ai un code d'invitation")),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
