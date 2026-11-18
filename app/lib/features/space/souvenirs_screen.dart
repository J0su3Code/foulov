import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../src/rust/api/chat.dart';
import '../../src/rust/api/space.dart';
import '../../theme/foulov_theme.dart';
import '../../ui/love.dart';
import '../chat/chat_service.dart';
import '../chat/media_viewer.dart';
import '../chat/voice.dart';
import 'edit_profile_screen.dart';
import 'widgets.dart';

/// « Souvenirs » : tout ce que vous vous envoyez, rangé par mois, et vos albums à vous.
/// Tout est lu dans la base locale chiffrée : rien ne repasse par le serveur.
class SouvenirsScreen extends StatefulWidget {
  const SouvenirsScreen({super.key, required this.chat});

  final ChatService chat;

  @override
  State<SouvenirsScreen> createState() => _SouvenirsScreenState();
}

enum _Filter { all, albums, videos, voices }

class _SouvenirsScreenState extends State<SouvenirsScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text('Souvenirs', style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  for (final (f, label) in const [
                    (_Filter.all, 'Tout'),
                    (_Filter.albums, 'Albums'),
                    (_Filter.videos, 'Vidéos'),
                    (_Filter.voices, 'Vocaux'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _filter == f,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: switch (_filter) {
                _Filter.all => MediaGrid(
                  key: const ValueKey('all'),
                  chat: widget.chat,
                  header: _AlbumsStrip(chat: widget.chat),
                ),
                _Filter.videos => MediaGrid(key: const ValueKey('v'), chat: widget.chat, kind: 2),
                _Filter.albums => _AlbumsGrid(chat: widget.chat),
                _Filter.voices => _Voices(chat: widget.chat),
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ===================================================================== grille par mois

/// Photos et vidéos de la conversation, par mois. `kind` : 1 photos, 2 vidéos, `null` les deux.
/// `selection` : mode choix (pour un album), qui renvoie les identifiants cochés.
class MediaGrid extends StatefulWidget {
  const MediaGrid({super.key, required this.chat, this.kind, this.header, this.selection, this.only});

  final ChatService chat;
  final int? kind;
  final Widget? header;
  final ValueNotifier<Set<String>>? selection;

  /// Seulement ces messages (un album), dans cet ordre.
  final List<String>? only;

  @override
  State<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<MediaGrid> {
  static const _page = 120;
  final _scroll = ScrollController();
  final List<ChatMessage> _items = [];
  bool _more = true, _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.chat.addListener(_changed);
    widget.selection?.addListener(_redraw);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _load();
    });
  }

  @override
  void didUpdateWidget(MediaGrid old) {
    super.didUpdateWidget(old);
    if (old.only != widget.only) _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.chat.removeListener(_changed);
    widget.selection?.removeListener(_redraw);
    _scroll.dispose();
    super.dispose();
  }

  void _redraw() => setState(() {});

  // Nouvelle photo envoyée ou reçue : on relit (regroupé, pour ne pas relire à chaque accusé de réception).
  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  Future<void> _reload() async {
    final only = widget.only;
    List<ChatMessage> first;
    if (only != null) {
      first = [
        for (final id in only) ?await widget.chat.lookup(id),
      ].where((m) => m.media != null && !m.deleted).toList();
    } else {
      first = await chatMediaGallery(limit: _page, kind: widget.kind);
    }
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(first);
      _more = only == null && first.length == _page;
    });
  }

  Future<void> _load() async {
    if (_loading || !_more || _items.isEmpty) return;
    _loading = true;
    try {
      final last = _items.last;
      final next = await chatMediaGallery(
        beforeSentAt: last.sentAt,
        beforeId: last.id,
        limit: _page,
        kind: widget.kind,
      );
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
    // Regroupement par mois (ou une seule grille pour un album, dans son ordre).
    final groups = <String, List<ChatMessage>>{};
    for (final m in _items) {
      final d = DateTime.fromMillisecondsSinceEpoch(m.sentAt);
      final key = widget.only != null
          ? ''
          : '${monthsLong[d.month - 1][0].toUpperCase()}${monthsLong[d.month - 1].substring(1)} ${d.year}';
      groups.putIfAbsent(key, () => []).add(m);
    }
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        if (widget.header != null) SliverToBoxAdapter(child: widget.header),
        if (_items.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _Empty(album: widget.only != null))
        else
          for (final e in groups.entries) ...[
            if (e.key.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(12, e.key.isEmpty ? 12 : 0, 12, 0),
              sliver: SliverGrid.count(
                crossAxisCount: 3,
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
                children: [
                  for (final m in e.value)
                    _Tile(
                      m: m,
                      chat: widget.chat,
                      selected: widget.selection?.value.contains(m.id),
                      onSelect: widget.selection == null
                          ? null
                          : () {
                              final s = {...widget.selection!.value};
                              s.contains(m.id) ? s.remove(m.id) : s.add(m.id);
                              widget.selection!.value = s;
                              HapticFeedback.selectionClick();
                            },
                    ),
                ],
              ),
            ),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.m, required this.chat, this.selected, this.onSelect});

  final ChatMessage m;
  final ChatService chat;
  final bool? selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final md = m.media!;
    final ready = md.state == 1 || (m.fromMe && md.state == 0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: context.love.surface2,
        child: InkWell(
          onTap:
              onSelect ??
              (ready
                  ? () => openMediaViewer(context, chat, m)
                  : () => ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(content: Text('Encore en cours de téléchargement…')))),
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
              if (!ready && onSelect == null)
                const Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                ),
              if (selected != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected! ? context.cs.primary : Colors.black26,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: selected! ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
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
  const _Empty({this.album = false});

  final bool album;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const EntwinedHeart(size: 120),
          const SizedBox(height: 14),
          Text(
            album ? 'Un album tout neuf' : 'Vos souvenirs commencent ici',
            style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            album
                ? 'Ajoutez-y vos plus belles photos et vidéos.'
                : 'Les photos et vidéos que vous vous envoyez se rangent ici, mois après mois. '
                      'Elles restent chiffrées sur vos téléphones.',
            textAlign: TextAlign.center,
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ===================================================================== albums

class _AlbumsStrip extends StatelessWidget {
  const _AlbumsStrip({required this.chat});

  final ChatService chat;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: chat.space,
    builder: (context, _) => SizedBox(
      height: 150,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        children: [
          for (final a in chat.space.albums)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 128,
                child: _AlbumCard(chat: chat, album: a),
              ),
            ),
          SizedBox(
            width: chat.space.albums.isEmpty ? 150 : 72,
            child: _NewAlbum(chat: chat, big: chat.space.albums.isEmpty),
          ),
        ],
      ),
    ),
  );
}

class _AlbumsGrid extends StatelessWidget {
  const _AlbumsGrid({required this.chat});

  final ChatService chat;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: chat.space,
    builder: (context, _) => GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: .9,
      children: [
        for (final a in chat.space.albums) _AlbumCard(chat: chat, album: a),
        _NewAlbum(chat: chat, big: true),
      ],
    ),
  );
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.chat, required this.album});

  final ChatService chat;
  final Album album;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AlbumScreen(chat: chat, id: album.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                child: album.items.isEmpty
                    ? ColoredBox(
                        color: context.love.soft,
                        child: Icon(Icons.photo_album_outlined, color: context.cs.primary, size: 32),
                      )
                    : FutureBuilder(
                        future: chat.lookup(album.items.first),
                        builder: (context, snap) {
                          final t = snap.data?.media?.thumb;
                          return t == null
                              ? ColoredBox(color: context.love.surface2)
                              : Image.memory(t, fit: BoxFit.cover, gaplessPlayback: true);
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            '${album.items.length} ${album.items.length > 1 ? 'souvenirs' : 'souvenir'}',
            style: TextStyle(fontSize: 11.5, color: context.cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _NewAlbum extends StatelessWidget {
  const _NewAlbum({required this.chat, this.big = false});

  final ChatService chat;
  final bool big;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: big ? 36 : 34),
    child: Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.cs.secondary, width: 1.6),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () => createAlbum(context, chat),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: context.cs.primary),
              if (big)
                Text(
                  'Nouvel album',
                  style: TextStyle(color: context.cs.primary, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Nouvel album : un titre, puis le choix des photos et vidéos.
Future<void> createAlbum(BuildContext context, ChatService chat) async {
  final title = await editText(
    context,
    title: 'Nouvel album',
    initial: '',
    max: 60,
    help: 'Par exemple : « Lisbonne 2025 ».',
  );
  if (title == null || title.trim().isEmpty || !context.mounted) return;
  final items = await pickMedia(context, chat, const {});
  if (items == null || !context.mounted) return;
  try {
    final a = await chat.space.saveAlbum(title: title, items: items);
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AlbumScreen(chat: chat, id: a.id),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('L\'album n\'a pas pu être créé.')));
    }
  }
}

/// Choisir des photos et vidéos de la conversation. Renvoie les identifiants, du plus récent au plus ancien.
Future<List<String>?> pickMedia(BuildContext context, ChatService chat, Set<String> initial) =>
    Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PickMedia(chat: chat, initial: initial),
      ),
    );

class _PickMedia extends StatefulWidget {
  const _PickMedia({required this.chat, required this.initial});

  final ChatService chat;
  final Set<String> initial;

  @override
  State<_PickMedia> createState() => _PickMediaState();
}

class _PickMediaState extends State<_PickMedia> {
  late final _sel = ValueNotifier<Set<String>>({...widget.initial});

  @override
  void dispose() {
    _sel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _sel,
    builder: (context, s, _) => Scaffold(
      appBar: AppBar(
        title: Text(s.isEmpty ? 'Choisir des souvenirs' : '${s.length} choisi${s.length > 1 ? 's' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, s.toList()), child: const Text('Valider')),
          const SizedBox(width: 8),
        ],
      ),
      body: MediaGrid(chat: widget.chat, selection: _sel),
    ),
  );
}

class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key, required this.chat, required this.id});

  final ChatService chat;
  final String id;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: chat.space,
    builder: (context, _) {
      final a = chat.space.albums.where((x) => x.id == id).firstOrNull;
      if (a == null) {
        // Supprimé (ici ou par l'autre).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).maybePop();
        });
        return const Scaffold();
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(a.title),
          actions: [
            IconButton(
              tooltip: 'Ajouter des souvenirs',
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: () async {
                final items = await pickMedia(context, chat, a.items.toSet());
                if (items == null) return;
                // Les souvenirs déjà présents gardent leur place ; les nouveaux s'ajoutent à la fin.
                final keep = [
                  for (final i in a.items)
                    if (items.contains(i)) i,
                ];
                final added = [
                  for (final i in items)
                    if (!a.items.contains(i)) i,
                ];
                await chat.space.saveAlbum(id: a.id, title: a.title, items: [...keep, ...added]);
              },
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final t = await editText(context, title: 'Renommer l\'album', initial: a.title, max: 60);
                  if (t != null && t.trim().isNotEmpty) await chat.space.saveAlbum(id: a.id, title: t, items: a.items);
                } else if (v == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Supprimer cet album ?'),
                      content: const Text(
                        'Les photos et vidéos restent dans vos souvenirs. Seul l\'album disparaît, chez vous deux.',
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
                      ],
                    ),
                  );
                  if (ok == true) await chat.space.deleteAlbum(a.id);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Renommer')),
                PopupMenuItem(value: 'delete', child: Text('Supprimer l\'album')),
              ],
            ),
          ],
        ),
        body: MediaGrid(chat: chat, only: a.items),
      );
    },
  );
}

// ===================================================================== vocaux

class _Voices extends StatefulWidget {
  const _Voices({required this.chat});

  final ChatService chat;

  @override
  State<_Voices> createState() => _VoicesState();
}

class _VoicesState extends State<_Voices> {
  List<ChatMessage>? _items;

  @override
  void initState() {
    super.initState();
    chatMediaGallery(limit: 300, kind: 3).then((v) => mounted ? setState(() => _items = v) : null);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Vos messages vocaux se retrouveront ici, pour réentendre sa voix quand vous voulez.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cs.onSurfaceVariant),
          ),
        ),
      );
    }
    final p = VoicePlayback.instance;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final m = items[i];
          final ready = m.media!.state == 1 || (m.fromMe && m.media!.state == 0);
          final d = DateTime.fromMillisecondsSinceEpoch(m.sentAt);
          return LoveCard(
            padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: ready ? () => p.toggle(m) : null,
                  icon: Icon(p.isPlaying(m.id) ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                  iconSize: 40,
                  color: context.cs.primary,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.fromMe ? 'Toi' : widget.chat.partnerLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${frDate(d, year: d.year != DateTime.now().year)} · ${formatDuration(m.media!.durationMs)}',
                        style: TextStyle(fontSize: 12.5, color: context.cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (p.current == m.id)
                  SizedBox(
                    width: 60,
                    child: LinearProgressIndicator(value: p.progress(m.id), backgroundColor: context.love.surface2),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
