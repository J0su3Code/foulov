import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../../src/rust/api/chat.dart';
import 'video_proxy.dart';

/// Enregistrement d'un message vocal (AAC, mono). Le fichier en clair n'existe que le temps de l'enregistrement :
/// il est chiffré puis effacé à l'envoi, ou effacé tout de suite si on annule.
class VoiceRecorder extends ChangeNotifier {
  final _rec = AudioRecorder();
  StreamSubscription<Amplitude>? _amp;
  Timer? _tick;
  String? _path;
  DateTime? _startedAt;

  /// Amplitudes relevées toutes les 100 ms (0 à 1), pour l'onde affichée pendant l'enregistrement.
  final List<double> levels = [];
  Duration elapsed = Duration.zero;
  bool get recording => _path != null;

  static const maxDuration = Duration(minutes: 10);

  /// Faux si le micro est refusé.
  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/vocal-${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1),
      path: path,
    );
    _path = path;
    _startedAt = DateTime.now();
    levels.clear();
    elapsed = Duration.zero;
    _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
      // dBFS : -60 (silence) à 0 (fort).
      levels.add(((a.current + 60) / 60).clamp(0.0, 1.0));
      notifyListeners();
    });
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      elapsed = DateTime.now().difference(_startedAt!);
      notifyListeners();
    });
    return true;
  }

  /// Arrête et renvoie (fichier, durée, forme d'onde sur 64 barres de 0 à 255).
  Future<(String, int, List<int>)?> stop() async {
    final path = _path;
    if (path == null) return null;
    await _cleanup();
    await _rec.stop();
    final ms = elapsed.inMilliseconds;
    if (ms < 700) {
      await _delete(path); // geste involontaire
      return null;
    }
    return (path, ms, waveform(levels));
  }

  Future<void> cancel() async {
    final path = _path;
    await _cleanup();
    await _rec.cancel();
    if (path != null) await _delete(path);
  }

  Future<void> _cleanup() async {
    _path = null;
    await _amp?.cancel();
    _tick?.cancel();
    // L'écran a pu être fermé entre-temps (déconnexion pendant un enregistrement).
    if (!_disposed) notifyListeners();
  }

  static Future<void> _delete(String p) async {
    try {
      await File(p).delete();
    } catch (_) {}
  }

  /// Réduit les niveaux relevés à 64 barres (le maximum de chaque tranche, pour garder les pics de la voix).
  static List<int> waveform(List<double> levels) {
    if (levels.isEmpty) return List.filled(64, 0);
    return List.generate(64, (i) {
      final a = i * levels.length ~/ 64, b = max(a + 1, (i + 1) * levels.length ~/ 64);
      final v = levels.sublist(a, min(b, levels.length)).fold(0.0, max);
      return (v * 255).round();
    });
  }

  bool _disposed = false;

  @override
  void dispose() {
    // Fermeture pendant un enregistrement : on l'abandonne (et son fichier) avant de libérer l'enregistreur.
    _disposed = true;
    final path = _path;
    _path = null;
    unawaited(_amp?.cancel());
    _tick?.cancel();
    unawaited(_rec.cancel().whenComplete(_rec.dispose));
    if (path != null) unawaited(_delete(path));
    super.dispose();
  }
}

/// Lecture des vocaux : un seul à la fois, déchiffré à la volée par le serveur local (jamais en clair sur le disque).
class VoicePlayback extends ChangeNotifier {
  VoicePlayback._();
  static final instance = VoicePlayback._();

  VideoPlayerController? _c;
  String? current;

  bool isPlaying(String id) => current == id && (_c?.value.isPlaying ?? false);

  /// Avancement de 0 à 1 du vocal en cours (0 pour les autres).
  double progress(String id) {
    final c = _c;
    if (current != id || c == null || !c.value.isInitialized || c.value.duration.inMilliseconds == 0) return 0;
    return (c.value.position.inMilliseconds / c.value.duration.inMilliseconds).clamp(0.0, 1.0);
  }

  Duration position(String id) => current == id ? (_c?.value.position ?? Duration.zero) : Duration.zero;

  Future<void> toggle(ChatMessage m) async {
    if (current == m.id && _c != null) {
      final c = _c!;
      if (c.value.isPlaying) {
        await c.pause();
      } else {
        if (c.value.position >= c.value.duration) await c.seekTo(Duration.zero);
        await c.play();
      }
      notifyListeners();
      return;
    }
    await stop();
    current = m.id;
    notifyListeners();
    try {
      final c = VideoPlayerController.networkUrl(await VideoProxy.url(m.id));
      _c = c;
      await c.initialize();
      c.addListener(() {
        if (c.value.isInitialized && c.value.position >= c.value.duration && !c.value.isPlaying) {
          c.seekTo(Duration.zero);
          c.pause();
        }
        notifyListeners();
      });
      await c.play();
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] vocal : $e');
      await stop();
    }
  }

  Future<void> stop() async {
    final c = _c;
    _c = null;
    current = null;
    notifyListeners();
    await c?.dispose();
  }
}
