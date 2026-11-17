import 'dart:async';

import 'package:flutter/material.dart';

import '../../src/rust/api/chat.dart';
import '../../ui/love.dart';
import 'chat_service.dart';
import 'media_viewer.dart';

/// Onglet « Saisons » : toutes vos photos et vidéos, rangées par saison.
/// Tout est lu dans la base locale chiffrée : rien ne repasse par le serveur.
class SeasonsScreen extends StatefulWidget {
  const SeasonsScreen({super.key, required this.service});

  final ChatService service;

  @override
  State<SeasonsScreen> createState() => _SeasonsScreenState();
}

enum _Filter { all, photos, videos }

class _SeasonsScreenState extends State<SeasonsScreen> {
  static const _page = 90;
  final _scroll = ScrollController();
  final List<ChatMessage> _items = [];
  _Filter _filter = _Filter.all;
  bool _more = true, _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.service.addListener(_changed);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.service.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  // Nouvelle photo envoyée ou reçue : on relit la première page (regroupé, pour ne pas relire à chaque accusé).
  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  int? get _kind => switch (_filter) {
    _Filter.all => null,
    _Filter.photos => 1,
    _Filter.videos => 2,
  };

  Future<void> _reload() async {
    final first = await chatMediaGallery(limit: _page, kind: _kind);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(first);
      _more = first.length == _page;
    });
  }

  Future<void> _load() async {
    if (_loading || !_more || _items.isEmpty) return;
    _loading = true;
    try {
      final last = _items.last;
      final next = await chatMediaGallery(beforeSentAt: last.sentAt, beforeId: last.id, limit: _page, kind: _kind);
      if (!mounted) return;
      setState(() {
        _items.addAll(next);
        _more = next.length == _page;
      });
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final groups = <(String, List<ChatMessage>)>[];
    for (final m in _items) {
      final label = seasonLabel(DateTime.fromMillisecondsSinceEpoch(m.sentAt));
      if (groups.isEmpty || groups.last.$1 != label) groups.add((label, []));
      groups.last.$2.add(m);
    }
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text('Saisons', style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    for (final (f, label) in [
                      (_Filter.all, 'Tout'),
                      (_Filter.photos, 'Photos'),
                      (_Filter.videos, 'Vidéos'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _filter == f,
                          showCheckmark: false,
                          selectedColor: cs.primary,
                          labelStyle: TextStyle(color: _filter == f ? cs.onPrimary : cs.onSurface),
                          onSelected: (_) {
                            setState(() => _filter = f);
                            _reload();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_items.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: _Empty())
            else
              for (final (label, items) in groups) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(label, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Text(_count(items), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _Tile(m: items[i], service: widget.service),
                  ),
                ),
              ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  static String _count(List<ChatMessage> items) {
    final v = items.where((m) => m.media!.kind == 2).length;
    final p = items.length - v;
    return [if (p > 0) '$p photo${p > 1 ? 's' : ''}', if (v > 0) '$v vidéo${v > 1 ? 's' : ''}'].join(' · ');
  }
}

/// « Printemps 2026 », « Hiver 2026 » (décembre compte dans l'hiver de l'année qui suit).
String seasonLabel(DateTime d) {
  final m = d.month;
  if (m >= 3 && m <= 5) return 'Printemps ${d.year}';
  if (m >= 6 && m <= 8) return 'Été ${d.year}';
  if (m >= 9 && m <= 11) return 'Automne ${d.year}';
  return 'Hiver ${m == 12 ? d.year + 1 : d.year}';
}

class _Tile extends StatelessWidget {
  const _Tile({required this.m, required this.service});

  final ChatMessage m;
  final ChatService service;

  @override
  Widget build(BuildContext context) {
    final md = m.media!;
    final ready = md.state == 1 || (m.fromMe && md.state == 0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: InkWell(
          onTap: ready
              ? () => openMediaViewer(context, service, m)
              : () => ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Encore en cours de téléchargement…'))),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(md.thumb, fit: BoxFit.cover, gaplessPlayback: true),
              if (md.kind == 2)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                        Text(formatDuration(md.durationMs), style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              if (!ready)
                const Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const EntwinedHeart(size: 130),
          const SizedBox(height: 14),
          Text('Vos saisons commencent ici', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Les photos et vidéos que vous vous envoyez se rangent ici, saison après saison. '
            'Elles restent chiffrées sur vos téléphones.',
            textAlign: TextAlign.center,
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }
}
