import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../src/rust/api/chat.dart';
import '../../theme/foulov_theme.dart';
import '../../ui/love.dart';
import 'chat_service.dart';
import '../space/moments.dart';
import '../space/personalize_screen.dart';
import '../space/widgets.dart';
import 'bubble_look.dart';
import 'media_preview.dart';
import 'space_screen.dart';
import 'expression_panel.dart';
import 'stickers.dart';
import 'view_once.dart';
import 'voice.dart';
import 'media_viewer.dart';

/// La conversation du couple : le cœur de l'app.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.service,
    required this.since,
    required this.onShowSymbols,
    required this.onSignOut,
    this.active = true,
    this.onBack,
    this.back,
    this.bottomInset = 0,
  });

  /// Retour du système : la conversation le traite d'abord (voir [ChatBack]).
  final ChatBack? back;

  final ChatService service;

  /// Date de création de l'espace : « Jour N ».
  final DateTime? since;
  final VoidCallback onShowSymbols;
  final VoidCallback onSignOut;

  /// Onglet affiché : sinon, les messages reçus ne sont pas marqués « lus ».
  final bool active;

  /// Flèche de retour vers « Nous » (la conversation occupe tout l'écran, sans barre du bas).
  final VoidCallback? onBack;

  /// Marge de la barre de gestes du système, lue au-dessus du Scaffold parent (qui la retire à ses enfants).
  final double bottomInset;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// Relie le bouton retour de l'accueil à la conversation : fermer le panneau des stickers ou annuler une
/// modification passe avant le changement d'onglet.
class ChatBack {
  bool Function()? _handler;

  /// Vrai si la conversation a consommé le retour.
  bool consume() => _handler?.call() ?? false;
}

const _reactions = ['❤️', '🥰', '😂', '😮', '😢', '🔥'];

/// Photos et vidéos envoyées d'affilée (moins de 2 minutes entre chacune) : regroupées en album, comme WhatsApp.
const _albumGapMs = 120000;

bool _isPhotoOrVideo(ChatMessage m) =>
    !m.deleted && (m.media?.kind == 1 || m.media?.kind == 2) && m.quote == null && !_isViewOnce(m);

/// Vue unique : jamais dans un album, jamais d'aperçu.
bool _isViewOnce(ChatMessage m) => (m.media?.viewOnce ?? 0) != 0;

/// Peut rejoindre un album : ni légende, ni réponse (seule la première photo du lot peut en avoir).
bool _plainMedia(ChatMessage m) => _isPhotoOrVideo(m) && m.body.isEmpty && m.replyTo == null;

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _list = ListController();
  ChatMessage? _replyTo;

  /// Message en cours de modification (le champ de saisie contient son texte).
  ChatMessage? _editing;

  /// Brouillon mis de côté pendant une modification, rendu ensuite.
  String _draft = '';
  bool _showJump = false;

  /// Panneau émojis et stickers ouvert à la place du clavier.
  bool _panel = false;

  /// Hauteur du clavier, retenue pour que le panneau des stickers prenne exactement sa place.
  double _keyboard = 0;

  /// Message mis en évidence après un toucher sur une citation.
  String? _highlight;
  int _flash = 0;

  /// Messages arrivés pendant que l'écran est ouvert : ils apparaissent avec une animation (une seule fois).
  final Set<String> _entering = {};
  String? _newest;

  /// Éléments affichés (du plus récent au plus ancien) : un message, ou un album (du plus ancien au plus récent).
  List<List<ChatMessage>> _items = const [];
  final Map<String, int> _index = {};

  ChatService get _s => widget.service;

  @override
  void initState() {
    super.initState();
    _newest = _s.messages.firstOrNull?.id;
    _s.addListener(_changed);
    _s.space.addListener(_changed);
    _s.visible = widget.active;
    _scroll.addListener(_onScroll);
    _input.addListener(() {
      if (_editing == null) _s.typing(_input.text.trim().isNotEmpty);
      setState(() {});
    });
    _focus.addListener(() {
      if (_focus.hasFocus && _panel) setState(() => _panel = false);
    });
    unawaited(StickerLibrary.instance.ensureLoaded());
    widget.back?._handler = _handleBack;
  }

  bool _handleBack() {
    if (_panel) {
      setState(() => _panel = false);
      return true;
    }
    if (_editing != null) {
      _cancelEdit();
      return true;
    }
    if (_replyTo != null) {
      setState(() => _replyTo = null);
      return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _s.visible = widget.active;
    if (old.back != widget.back) {
      old.back?._handler = null;
      widget.back?._handler = _handleBack;
    }
  }

  @override
  void dispose() {
    if (widget.back?._handler == _handleBack) widget.back?._handler = null;
    _recorder.dispose();
    unawaited(VoicePlayback.instance.stop());
    _s.visible = false;
    _s.removeListener(_changed);
    _s.space.removeListener(_changed);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    _list.dispose();
    super.dispose();
  }

  void _changed() {
    final top = _s.messages.firstOrNull;
    if (top != null && top.id != _newest) {
      // Nouveaux messages en haut de liste (les plus récents) : on les anime.
      for (final m in _s.messages) {
        if (m.id == _newest) break;
        _entering.add(m.id);
      }
      _newest = top.id;
    }
    // Le message en cours de modification a été supprimé entre-temps.
    final e = _editing;
    if (e != null && (_s.byId(e.id)?.deleted ?? false)) _cancelEdit();
    if (mounted) setState(() {});
  }

  /// Regroupe les photos et vidéos envoyées d'affilée en albums.
  void _regroup() {
    final msgs = _s.messages;
    final items = <List<ChatMessage>>[];
    _index.clear();
    var i = 0;
    while (i < msgs.length) {
      var j = i;
      if (_plainMedia(msgs[i])) {
        while (j + 1 < msgs.length) {
          final older = msgs[j + 1], cur = msgs[j];
          final fits =
              _isPhotoOrVideo(older) &&
              older.fromMe == cur.fromMe &&
              cur.sentAt - older.sentAt <= _albumGapMs &&
              _sameDay(cur.sentAt, older.sentAt);
          if (!fits) break;
          j++;
          if (!_plainMedia(older)) break; // la première du lot (avec légende ou réponse) ferme l'album
        }
      }
      final group = msgs.sublist(i, j + 1).reversed.toList();
      for (final m in group) {
        _index[m.id] = items.length;
      }
      items.add(group);
      i = j + 1;
    }
    _items = items;
  }

  void _onScroll() {
    final p = _scroll.position;
    if (p.pixels > p.maxScrollExtent - 800) _s.loadMore();
    final jump = p.pixels > 400;
    if (jump != _showJump) setState(() => _showJump = jump);
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    setState(() => _showJump = false);
  }

  /// Toucher une citation : on remonte jusqu'au message cité, qui s'illumine un instant (comme WhatsApp).
  Future<void> _jumpTo(String id) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    final found = await _s.loadUntil(id);
    if (!mounted) return;
    if (!found) {
      messenger.showSnackBar(const SnackBar(content: Text('Ce message n\'est plus dans la conversation.')));
      return;
    }
    setState(_regroup);
    await WidgetsBinding.instance.endOfFrame;
    final i = _index[id];
    if (i == null || !_scroll.hasClients || !mounted) return;
    _list.animateToItem(
      index: i + (_s.partnerTyping ? 1 : 0),
      scrollController: _scroll,
      alignment: .5,
      duration: (d) => Duration(milliseconds: (250 + d / 10).clamp(250, 700).round()),
      curve: (_) => Curves.easeInOutCubic,
    );
    final token = ++_flash;
    setState(() => _highlight = id);
    Timer(const Duration(milliseconds: 1700), () {
      if (mounted && _flash == token) setState(() => _highlight = null);
    });
  }

  Future<void> _send() async {
    if (_editing != null) return _saveEdit();
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final reply = _replyTo?.id;
    HapticFeedback.lightImpact();
    _input.clear();
    setState(() => _replyTo = null);
    try {
      await _s.send(text, replyTo: reply);
      ChatWallpaper.bump(); // le fond glisse doucement, comme une respiration
      _toBottom();
    } catch (e) {
      _input.text = text;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ce message n\'a pas pu être préparé. Réessaie.')));
    }
  }

  // ------------------------------------------------------------------ modifier un message

  void _startEdit(ChatMessage m) {
    HapticFeedback.selectionClick();
    _s.typing(false);
    if (_editing == null) _draft = _input.text;
    setState(() {
      _editing = m;
      _replyTo = null;
      _panel = false;
    });
    _input.text = m.body;
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _focus.requestFocus();
  }

  void _cancelEdit() {
    _editing = null;
    _input.text = _draft;
    _input.selection = TextSelection.collapsed(offset: _draft.length);
    _draft = '';
    if (mounted) setState(() {});
  }

  Future<void> _saveEdit() async {
    final m = _editing!;
    final text = _input.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (m.media == null && text.isEmpty) return;
    if (text == m.body.trim()) return _cancelEdit();
    if (!ChatService.canEdit(m)) {
      _cancelEdit();
      messenger.showSnackBar(
        const SnackBar(content: Text('Un message se modifie pendant 15 minutes après l\'envoi : ce délai est passé.')),
      );
      return;
    }
    HapticFeedback.lightImpact();
    try {
      await _s.edit(m.id, text);
      _cancelEdit();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('La modification n\'a pas pu être enregistrée.')));
    }
  }

  // ------------------------------------------------------------------ pièces jointes

  /// Trombone : galerie (plusieurs photos et vidéos d'un coup), appareil photo ou vidéo.
  Future<void> _attach() async {
    // Le clavier ne doit pas remonter par-dessus la galerie, ni au retour.
    _focus.unfocus();
    final cs = Theme.of(context).colorScheme;
    Widget option(String id, IconData icon, String label, Color color) => InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pop(context, id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 27),
            ),
            const SizedBox(height: 7),
            Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface)),
          ],
        ),
      ),
    );
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(child: option('gallery', Icons.photo_library_rounded, 'Galerie', const Color(0xFF8E5CF7))),
              Expanded(child: option('photo', Icons.photo_camera_rounded, 'Photo', const Color(0xFFE8417A))),
              Expanded(child: option('video', Icons.videocam_rounded, 'Vidéo', const Color(0xFFF2994A))),
              Expanded(child: option('sticker', Icons.emoji_emotions_rounded, 'Sticker', const Color(0xFF2EC4B6))),
            ],
          ),
        ),
      ),
    );
    if (choice == 'sticker') return _toggleStickers();
    if (choice != null) await _pick(choice);
  }

  /// Choisit, montre l'aperçu (légende, retirer, ajouter), puis envoie dans l'ordre. Le texte en cours devient la
  /// légende ; une galerie de plusieurs photos s'affiche en album chez vous deux.
  Future<void> _pick(String source) async {
    _focus.unfocus();
    final picker = ImagePicker();
    final List<XFile> files;
    try {
      files = switch (source) {
        'photo' => [?await picker.pickImage(source: ImageSource.camera, requestFullMetadata: false)],
        'video' => [?await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 5))],
        _ => await picker.pickMultipleMedia(limit: maxPicked, requestFullMetadata: false),
      };
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Autorise l\'accès aux photos ou à l\'appareil photo dans les réglages.')),
        );
      }
      return;
    }
    if (files.isEmpty || !mounted) return;
    final picked = await previewMedia(context, files, caption: _input.text.trim(), to: _s.partnerLabel);
    if (mounted) FocusScope.of(context).unfocus();
    if (picked == null || !mounted) return;
    final (items, caption, viewOnce) = picked;
    final reply = _replyTo?.id;
    _input.clear();
    setState(() => _replyTo = null);
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    for (final (i, f) in items.indexed) {
      final progress = ValueNotifier<double>(0);
      if (f.video) {
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(minutes: 10),
            content: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, p, _) => Row(
                children: [
                  const Expanded(child: Text('Préparation de la vidéo…')),
                  SizedBox(width: 90, child: LinearProgressIndicator(value: p > 0 ? p : null)),
                ],
              ),
            ),
          ),
        );
      }
      try {
        if (f.video) {
          await _s.sendVideo(
            f.file.path,
            caption: i == 0 ? caption : '',
            replyTo: i == 0 ? reply : null,
            onProgress: (p) => progress.value = p,
            viewOnce: viewOnce,
          );
        } else {
          await _s.sendPhoto(
            f.file.path,
            caption: i == 0 ? caption : '',
            replyTo: i == 0 ? reply : null,
            viewOnce: viewOnce,
          );
        }
        _toBottom();
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              f.video ? 'Cette vidéo n\'a pas pu être préparée.' : 'Cette photo n\'a pas pu être préparée.',
            ),
          ),
        );
      } finally {
        if (f.video) messenger.hideCurrentSnackBar();
        progress.dispose();
      }
    }
  }

  // ------------------------------------------------------------------ stickers

  void _toggleStickers() {
    HapticFeedback.selectionClick();
    if (_panel) {
      setState(() => _panel = false);
      _focus.requestFocus();
      return;
    }
    _focus.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() => _panel = true);
  }

  Future<void> _sendSticker(Sticker st, Uint8List bytes) async {
    HapticFeedback.lightImpact();
    final reply = _replyTo?.id;
    setState(() => _replyTo = null);
    try {
      final thumb = await stickerThumb(bytes);
      await _s.sendSticker(bytes, st.mime, st.width, st.height, thumb, replyTo: reply);
      unawaited(StickerLibrary.instance.used(st.id));
      _toBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ce sticker n\'a pas pu être envoyé.')));
      }
    }
  }

  // ------------------------------------------------------------------ vocaux

  final _recorder = VoiceRecorder();

  Future<void> _startVoice() async {
    HapticFeedback.mediumImpact();
    await VoicePlayback.instance.stop();
    if (!await _recorder.start() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Autorise le micro dans les réglages du téléphone pour envoyer des vocaux.')),
      );
    }
  }

  Future<void> _sendVoice() async {
    final r = await _recorder.stop();
    if (r == null) return;
    HapticFeedback.lightImpact();
    final reply = _replyTo?.id;
    setState(() => _replyTo = null);
    try {
      await _s.sendVoice(r.$1, r.$2, r.$3, replyTo: reply);
      _toBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ce vocal n\'a pas pu être envoyé.')));
      }
    }
  }

  void _reply(ChatMessage m) {
    HapticFeedback.selectionClick();
    if (_editing != null) _cancelEdit();
    setState(() => _replyTo = m);
    if (!_panel) _focus.requestFocus();
  }

  /// Appui long : réactions, puis Répondre, Modifier, Copier, Sticker, Supprimer. Pour un album : tout le lot.
  Future<void> _actions(List<ChatMessage> group) async {
    final m = group.first;
    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;
    final sticker = m.media?.kind == 4;
    final album = group.length > 1;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in _reactions)
                    InkResponse(
                      onTap: () => Navigator.pop(context, 'r:$e'),
                      radius: 28,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: m.myReaction == e ? cs.secondary.withValues(alpha: .25) : Colors.transparent,
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 30)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Répondre'),
                onTap: () => Navigator.pop(context, 'reply'),
              ),
              if (ChatService.canEdit(m) && !_isViewOnce(m))
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(m.media == null ? 'Modifier' : 'Modifier la légende'),
                  onTap: () => Navigator.pop(context, 'edit'),
                ),
              if (m.body.isNotEmpty && !_isViewOnce(m))
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copier'),
                  onTap: () => Navigator.pop(context, 'copy'),
                ),
              if (sticker)
                ListTile(
                  leading: const Icon(Icons.star_outline_rounded),
                  title: const Text('Ajouter aux favoris ou enregistrer'),
                  onTap: () => Navigator.pop(context, 'sticker'),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(album ? 'Supprimer ces ${group.length} pour moi' : 'Supprimer pour moi'),
                onTap: () => Navigator.pop(context, 'del-me'),
              ),
              if (m.fromMe)
                ListTile(
                  leading: Icon(Icons.delete_forever_outlined, color: cs.error),
                  title: Text(
                    album ? 'Supprimer ces ${group.length} pour nous deux' : 'Supprimer pour nous deux',
                    style: TextStyle(color: cs.error),
                  ),
                  onTap: () => Navigator.pop(context, 'del-both'),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'reply') _reply(m);
    if (choice == 'edit') _startEdit(m);
    if (choice == 'sticker') await showStickerSheet(context, _s, m);
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.body));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copié')));
    }
    if (choice.startsWith('r:')) await _s.react(m.id, choice.substring(2));
    if (choice.startsWith('del-') && mounted) {
      final both = choice == 'del-both';
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(both ? 'Supprimer pour vous deux ?' : 'Supprimer pour toi ?'),
          content: Text(
            both
                ? 'Le message disparaît aussi du téléphone de ton amour (s\'il l\'a déjà vu, il a pu le lire). '
                      'Le fichier chiffré est effacé du serveur.'
                : 'Le message disparaît seulement de ce téléphone. Ton amour le garde.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
          ],
        ),
      );
      if (ok != true) return;
      HapticFeedback.mediumImpact();
      try {
        for (final x in group) {
          both ? await _s.deleteForBoth(x.id) : await _s.deleteForMe(x.id);
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La suppression n\'a pas abouti.')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    _regroup();
    final items = _items;
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    // Hauteur du clavier : relevée seulement pendant qu'il s'ouvre (en se fermant, elle diminue image par image).
    if (_focus.hasFocus && !_panel && kb > _keyboard) {
      _keyboard = min(kb, MediaQuery.sizeOf(context).height * .5);
    }
    final panelHeight = _keyboard > 0 ? _keyboard : 300 + widget.bottomInset;
    // Sans barre d'application, c'est à nous de garder lisibles l'heure et la batterie en haut de l'écran.
    final night = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: night ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: BubbleLook.from(
        _s.space,
        child: Scaffold(
          backgroundColor: cs.surface,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _Header(
                  onBack: widget.onBack,
                  service: _s,
                  since: widget.since,
                  onShowSymbols: widget.onShowSymbols,
                  onSignOut: widget.onSignOut,
                ),
                if (_s.profile.myName == null)
                  _NameNudge(service: _s, onShowSymbols: widget.onShowSymbols, onSignOut: widget.onSignOut),
                if (_s.partnerKeyChanged) _KeyChanged(onVerify: widget.onShowSymbols),
                Expanded(
                  child: ChatWallpaper(
                    space: _s.space,
                    child: Stack(
                      children: [
                        if (items.isEmpty)
                          const _Empty()
                        else
                          SuperListView.builder(
                            controller: _scroll,
                            listController: _list,
                            reverse: true,
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            itemCount: items.length + 1 + (_s.partnerTyping ? 1 : 0),
                            // Les bulles gardent leur état (photo déjà déchiffrée) quand un message arrive.
                            findChildIndexCallback: (key) {
                              if (key is! ValueKey<String>) return null;
                              final i = _index[key.value];
                              return i == null ? null : i + (_s.partnerTyping ? 1 : 0);
                            },
                            itemBuilder: (context, i) {
                              // Les trois points de « écrit… », tout en bas de la conversation.
                              if (_s.partnerTyping) {
                                if (i == 0) return const _TypingBubble();
                                i -= 1;
                              }
                              if (i == items.length) return _s.hasMore ? const _Loading() : const _E2EBadge();
                              final g = items[i];
                              final m = g.first;
                              final older = i + 1 < items.length ? items[i + 1].last : null;
                              final newer = i > 0 ? items[i - 1].first : null;
                              final newDay = older == null || !_sameDay(older.sentAt, m.sentAt);
                              final groupTop = newDay || older.fromMe != m.fromMe || m.sentAt - older.sentAt > 180000;
                              final last = g.last;
                              final groupBottom =
                                  newer == null ||
                                  newer.fromMe != m.fromMe ||
                                  newer.sentAt - last.sentAt > 180000 ||
                                  !_sameDay(newer.sentAt, last.sentAt);
                              var entering = false;
                              for (final x in g) {
                                if (_entering.remove(x.id)) entering = true;
                              }
                              final bubble = _Flash(
                                on: _highlight != null && g.any((x) => x.id == _highlight),
                                child: _Bubble(
                                  group: g,
                                  service: _s,
                                  groupTop: groupTop,
                                  groupBottom: groupBottom,
                                  entering: entering,
                                  onReply: () => _reply(m),
                                  onActions: () => _actions(g),
                                  onLove: () => _s.react(m.id, '❤️'),
                                  onJump: _jumpTo,
                                ),
                              );
                              return KeyedSubtree(
                                key: ValueKey(m.id),
                                child: newDay ? Column(children: [_DaySeparator(m.sentAt), bubble]) : bubble,
                              );
                            },
                          ),
                        Positioned(
                          right: 16,
                          bottom: 12,
                          child: AnimatedScale(
                            scale: _showJump ? 1 : 0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutBack,
                            child: FloatingActionButton.small(
                              heroTag: null,
                              elevation: 2,
                              backgroundColor: cs.surfaceContainer,
                              foregroundColor: cs.onSurface,
                              onPressed: _toBottom,
                              child: const Icon(Icons.keyboard_arrow_down_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: _recorder,
                  // Plein écran (sans barre du bas) : la saisie reste au-dessus de la barre de gestes du système.
                  builder: (context, _) => Padding(
                    padding: EdgeInsets.only(bottom: kb == 0 && !_panel ? widget.bottomInset : 0),
                    child: _Composer(
                      service: _s,
                      recorder: _recorder,
                      onMic: _startVoice,
                      onVoiceSend: _sendVoice,
                      onVoiceCancel: _recorder.cancel,
                      controller: _input,
                      focus: _focus,
                      replyTo: _replyTo,
                      editing: _editing,
                      panel: _panel,
                      onCancelReply: () => setState(() => _replyTo = null),
                      onCancelEdit: _cancelEdit,
                      onSend: _send,
                      onAttach: _attach,
                      onCamera: () => _pick('photo'),
                      onStickers: _toggleStickers,
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: _panel
                      ? ExpressionPanel(
                          height: panelHeight,
                          bottomInset: _keyboard > 0 ? 0 : widget.bottomInset,
                          input: _input,
                          onSticker: _sendSticker,
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Le message cité s'illumine un instant quand on y arrive depuis une réponse.
class _Flash extends StatelessWidget {
  const _Flash({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: Duration(milliseconds: on ? 180 : 900),
    curve: Curves.easeOut,
    decoration: BoxDecoration(
      color: on ? Theme.of(context).colorScheme.primary.withValues(alpha: .16) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

// ===================================================================== dates

bool _sameDay(int a, int b) {
  final x = DateTime.fromMillisecondsSinceEpoch(a), y = DateTime.fromMillisecondsSinceEpoch(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

const _days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

String _dayLabel(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Aujourd\'hui';
  if (diff == 1) return 'Hier';
  if (diff < 7) return _days[d.weekday - 1][0].toUpperCase() + _days[d.weekday - 1].substring(1);
  return '${d.day} ${_months[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';
}

String _time(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ===================================================================== en-tête

class _Header extends StatelessWidget {
  const _Header({
    required this.service,
    required this.since,
    required this.onShowSymbols,
    required this.onSignOut,
    this.onBack,
  });

  final VoidCallback? onBack;
  final ChatService service;
  final DateTime? since;
  final VoidCallback onShowSymbols;
  final VoidCallback onSignOut;

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final space = service.space;
    final together = daysTogether(service.profile.togetherSince);
    final subtitle = together == null
        ? null
        : (together <= 1 ? 'Premier jour ensemble' : '${frNumber(together)} jours ensemble');
    return Material(
      color: cs.surface,
      child: Container(
        padding: EdgeInsets.fromLTRB(onBack == null ? 12 : 0, 6, 4, 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: cs.outline)),
        ),
        child: Row(
          children: [
            if (onBack != null) BackButton(onPressed: onBack),
            CoupleAvatar(
              space: space,
              size: 38,
              ring: space.theirsUnseen,
              onTap: space.theirs.isEmpty ? null : () => openMoments(context, space, mine: false),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.partnerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  // « écrit… » ou « en ligne » d'abord ; sinon vos jours ensemble.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: !service.connected
                        ? Text(
                            'hors ligne · tes messages partiront dès le retour du réseau',
                            key: const ValueKey('x'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                          )
                        : service.partnerTyping
                        ? Text(
                            'écrit…',
                            key: const ValueKey('t'),
                            style: TextStyle(fontSize: 12.5, color: cs.primary, fontWeight: FontWeight.w600),
                          )
                        : service.partnerOnline
                        ? Text(
                            'en ligne',
                            key: const ValueKey('o'),
                            style: TextStyle(fontSize: 12.5, color: context.love.ok),
                          )
                        : subtitle == null
                        ? const SizedBox.shrink()
                        : Text(
                            subtitle,
                            key: const ValueKey('d'),
                            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                          ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.palette_outlined),
              tooltip: 'Personnaliser',
              onPressed: () => _push(context, PersonalizeScreen(space: space)),
            ),
            IconButton(
              icon: const Icon(Icons.tune_rounded),
              tooltip: 'Réglages',
              onPressed: () =>
                  _push(context, SpaceScreen(service: service, onShowSymbols: onShowSymbols, onSignOut: onSignOut)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Invite douce, tant que tu n'as pas donné ton prénom à ton amour.
class _NameNudge extends StatelessWidget {
  const _NameNudge({required this.service, required this.onShowSymbols, required this.onSignOut});

  final ChatService service;
  final VoidCallback onShowSymbols, onSignOut;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(color: cs.secondary.withValues(alpha: .14), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Text('💌', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          const Expanded(child: Text('Dis à ton amour comment tu t\'appelles : ton prénom lui arrivera chiffré.')),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SpaceScreen(service: service, onShowSymbols: onShowSymbols, onSignOut: onSignOut),
              ),
            ),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }
}

class _KeyChanged extends StatelessWidget {
  const _KeyChanged({required this.onVerify});

  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer,
      child: InkWell(
        onTap: onVerify,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'La clé de ton amour a changé (nouveau téléphone ?). Ses nouveaux messages restent en attente '
                  'jusqu\'à ce que vous échangiez vos liens. Touche ici.',
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _E2EBadge extends StatelessWidget {
  const _E2EBadge();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainer.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Chiffré de bout en bout · clés vérifiées ensemble',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))),
  );
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator(this.ms);

  final int ms;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Center(
        child: Text(
          _dayLabel(ms),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
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
    // Défilable : avec le clavier ouvert, la place se réduit et le cœur rapetisse.
    return LoveBackground(
      count: 10,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EntwinedHeart(size: box.maxHeight < 520 ? 110 : 170),
                    const SizedBox(height: 16),
                    Text('Votre bulle est prête', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'Écris le premier mot doux. Il sera chiffré sur ce téléphone, et seul celui de ton amour pourra le lire.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    const _E2EBadge(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================================== bulle

class _Bubble extends StatefulWidget {
  const _Bubble({
    required this.group,
    required this.service,
    required this.groupTop,
    required this.groupBottom,
    required this.entering,
    required this.onReply,
    required this.onActions,
    required this.onLove,
    required this.onJump,
  });

  /// Un message, ou un album (du plus ancien au plus récent).
  final List<ChatMessage> group;
  final ChatService service;
  final bool groupTop, groupBottom, entering;
  final VoidCallback onReply, onActions, onLove;
  final void Function(String id) onJump;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: widget.entering ? 0 : 1,
  )..forward();
  late final AnimationController _heart = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  double _drag = 0;
  bool _armed = false;

  @override
  void dispose() {
    _in.dispose();
    _heart.dispose();
    super.dispose();
  }

  void _love() {
    HapticFeedback.lightImpact();
    if (widget.group.first.myReaction != '❤️') _heart.forward(from: 0);
    widget.onLove();
  }

  /// Toucher la bulle : une photo ou une vidéo s'ouvre, un sticker se garde. Un vocal se joue avec son bouton.
  VoidCallback? _tap(ChatMessage m) {
    final md = m.media;
    if (md == null || widget.group.length > 1) return null;
    // Vue unique : seul le destinataire l'ouvre, une fois, quand elle est téléchargée.
    if (md.viewOnce != 0) {
      return !m.fromMe && md.viewOnce == 1 && md.state == 1 ? () => openViewOnce(context, widget.service, m) : null;
    }
    if (md.kind == 4) return () => showStickerSheet(context, widget.service, m);
    if (md.kind == 1 || md.kind == 2) {
      final ready = md.state == 1 || (m.fromMe && md.state != 3);
      return ready ? () => openMediaViewer(context, widget.service, m) : null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final m = group.first;
    if (m.deleted) return _DeletedBubble(m: m, groupTop: widget.groupTop);
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final night = t.brightness == Brightness.dark;
    final mine = m.fromMe;
    final look = BubbleLook.of(context);
    final r = look.radius, tail = look.tail;
    // Coin resserré côté expéditeur ; en milieu de groupe, les bulles se « tiennent » par ce côté.
    final radius = BorderRadius.only(
      topLeft: !mine && !widget.groupTop ? tail : r,
      topRight: mine && !widget.groupTop ? tail : r,
      bottomLeft: mine ? r : tail,
      bottomRight: mine ? tail : r,
    );
    final fg = look.fg(context, mine);
    final reaction = {
      for (final x in group) ...[?x.theirReaction, ?x.myReaction],
    };
    Widget? quote;
    if (m.replyTo != null) {
      quote = _ReplyQuote(id: m.replyTo!, service: widget.service, inMine: mine, fg: fg, onTap: widget.onJump);
    }

    Widget bubble = group.length > 1
        ? _AlbumBubble(group: group, service: widget.service, radius: radius, fg: fg, mine: mine, quote: quote)
        : _isViewOnce(m)
        ? ViewOnceBubble(
            m: m,
            mine: mine,
            fg: fg,
            decoration: look.box(context, fromMe: mine, radius: radius),
            meta: _Meta(m: m, color: fg),
            quote: quote,
          )
        : m.media?.kind == 3
        ? _VoiceBubble(m: m, radius: radius, fg: fg, mine: mine, night: night, quote: quote)
        : m.media?.kind == 4
        ? _StickerBubble(m: m, service: widget.service, mine: mine, quote: quote)
        : m.media != null
        ? _MediaBubble(m: m, service: widget.service, radius: radius, fg: fg, mine: mine, night: night, quote: quote)
        : Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
            padding: quote == null && m.quote == null
                ? const EdgeInsets.fromLTRB(12, 8, 12, 7)
                : const EdgeInsets.fromLTRB(4, 4, 4, 7),
            decoration: look.box(context, fromMe: mine, radius: radius),
            child: _withQuote(
              quote: quote ?? (m.quote == null ? null : _MomentQuote(q: m.quote!, mine: mine, fg: fg)),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: quote == null && m.quote == null ? 0 : 7),
                child: quote == null && m.quote == null
                    ? Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 8,
                        children: [
                          Text(
                            m.body,
                            style: TextStyle(color: fg, fontSize: look.fontSize, height: 1.32),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: _Meta(m: m, color: fg),
                          ),
                        ],
                      )
                    // Sous une citation : le texte à gauche, l'heure en bas à droite.
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.body,
                            style: TextStyle(color: fg, fontSize: look.fontSize, height: 1.32),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: _Meta(m: m, color: fg),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );

    if (reaction.isNotEmpty) {
      bubble = Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 14), child: bubble),
          Positioned(
            bottom: 0,
            right: mine ? 10 : null,
            left: mine ? null : 10,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(reaction.join()),
              tween: Tween(begin: .4, end: 1),
              duration: const Duration(milliseconds: 380),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.surface, width: 2),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 6)],
                ),
                child: Text(reaction.join(' '), style: const TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ],
      );
    }

    // Cœur qui éclot au double toucher.
    bubble = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        bubble,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _heart,
            builder: (_, _) {
              if (_heart.value == 0 || _heart.value == 1) return const SizedBox.shrink();
              final v = _heart.value;
              final s = Curves.elasticOut.transform(min(1, v * 2.2)) * (1 + .3 * v);
              return Opacity(
                opacity: (1 - Curves.easeIn.transform(max(0, (v - .55) / .45))).clamp(0, 1),
                child: Transform.translate(
                  offset: Offset(0, -26 * v),
                  child: Transform.scale(
                    scale: s,
                    child: const Text('❤️', style: TextStyle(fontSize: 42)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );

    final semantics = '${mine ? 'Toi' : widget.service.partnerLabel}, ${_time(m.sentAt)} : ${_snippet(m).$2}';
    Widget row = Semantics(
      label: semantics,
      child: GestureDetector(
        onDoubleTap: _love,
        onTap: _tap(m),
        onLongPress: widget.onActions,
        onHorizontalDragUpdate: (d) {
          setState(() => _drag = (_drag + d.delta.dx).clamp(0, 80));
          if (!_armed && _drag > 56) {
            _armed = true;
            HapticFeedback.selectionClick();
          } else if (_armed && _drag < 56) {
            _armed = false;
          }
        },
        onHorizontalDragEnd: (_) {
          if (_armed) widget.onReply();
          setState(() {
            _drag = 0;
            _armed = false;
          });
        },
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Opacity(
              opacity: (_drag / 56).clamp(0, 1),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.reply_rounded, color: cs.secondary, size: 22 + (_armed ? 4 : 0)),
              ),
            ),
            AnimatedContainer(
              duration: Duration(milliseconds: _drag == 0 ? 220 : 0),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(_drag, 0, 0),
              child: Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: bubble),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: widget.groupTop ? 10 : 2),
      child: AnimatedBuilder(
        animation: _in,
        builder: (_, child) {
          final v = Curves.easeOutCubic.transform(_in.value);
          return Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset(0, 14 * (1 - v)),
              child: Transform.scale(
                scale: .94 + .06 * v,
                alignment: mine ? Alignment.bottomRight : Alignment.bottomLeft,
                child: child,
              ),
            ),
          );
        },
        child: row,
      ),
    );
  }
}

/// La citation prend toute la largeur de la bulle, le texte vient dessous (comme WhatsApp).
Widget _withQuote({required Widget? quote, required Widget child}) {
  if (quote == null) return child;
  return IntrinsicWidth(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [quote, const SizedBox(height: 4), child],
    ),
  );
}

/// Heure, « modifié » et coches d'envoi.
class _Meta extends StatelessWidget {
  const _Meta({required this.m, required this.color, this.solid = false});

  final ChatMessage m;
  final Color color;

  /// Sur une photo : texte blanc plein.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final soft = solid ? color : color.withValues(alpha: .62);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (m.editedAt != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              'modifié',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: soft),
            ),
          ),
        Text(_time(m.sentAt), style: TextStyle(fontSize: 11, color: soft)),
        if (m.fromMe) ...[const SizedBox(width: 3), _Status(m.status, color)],
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status(this.status, this.fg);

  final int status;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (status) {
      0 => (Icons.schedule_rounded, fg.withValues(alpha: .55), 'en attente'),
      1 => (Icons.check_rounded, fg.withValues(alpha: .7), 'envoyé'),
      2 => (Icons.done_all_rounded, fg.withValues(alpha: .7), 'distribué'),
      _ => (Icons.done_all_rounded, fg, 'lu'),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
      child: Icon(icon, key: ValueKey(status), size: 15, color: color, semanticLabel: label),
    );
  }
}

/// Réponse à un instant : sa miniature (ou son texte) et « Ton instant » / « Son instant ».
class _MomentQuote extends StatelessWidget {
  const _MomentQuote({required this.q, required this.mine, required this.fg});

  final Quote q;
  final bool mine;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: fg.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: q.thumb.isNotEmpty
                ? Image.memory(q.thumb, width: 34, height: 46, fit: BoxFit.cover)
                : Container(
                    width: 34,
                    height: 46,
                    decoration: BoxDecoration(gradient: LinearGradient(colors: MomentStyles.of(0))),
                    child: const Icon(Icons.format_quote_rounded, color: Colors.white, size: 18),
                  ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mine ? 'Réponse à son instant' : 'Réponse à ton instant',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg.withValues(alpha: .85)),
                ),
                if (q.text.isNotEmpty)
                  Text(
                    q.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: .75)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===================================================================== citations (réponses)

/// Ce qu'on montre d'un message cité : une icône (photo, vidéo, vocal, sticker) et un texte court.
(IconData?, String) _snippet(ChatMessage? q) {
  if (q == null) return (null, 'Message introuvable');
  if (q.deleted) return (Icons.block_rounded, 'Message supprimé');
  if (_isViewOnce(q)) return (Icons.looks_one_outlined, q.media?.kind == 2 ? 'Vidéo · vue unique' : 'Photo · vue unique');
  return switch (q.media?.kind) {
    1 => (Icons.photo_camera_rounded, q.body.isNotEmpty ? q.body : 'Photo'),
    2 => (Icons.videocam_rounded, q.body.isNotEmpty ? q.body : 'Vidéo'),
    3 => (Icons.mic_rounded, 'Message vocal (${formatDuration(q.media!.durationMs)})'),
    4 => (Icons.emoji_emotions_outlined, 'Sticker'),
    _ => (null, q.body),
  };
}

/// Couleur du nom et du filet de la citation : celle de la personne citée, lisible sur la bulle.
Color _quoteAccent(BuildContext context, {required bool inMine, required bool quotedMine}) {
  final look = BubbleLook.of(context);
  if (inMine && look.style <= 1) return Colors.white;
  // Comme WhatsApp : une couleur franche et différente pour chacun, lisible sur fond clair comme sombre.
  final night = Theme.of(context).brightness == Brightness.dark;
  final partner = look.theirs ?? (night ? const Color(0xFFB794FF) : const Color(0xFF7B4FD6));
  return quotedMine ? (night ? look.mine.$1 : look.mine.$2) : partner;
}

/// Bloc de citation façon WhatsApp : filet coloré, nom, aperçu (icône + texte) et miniature à droite.
class _QuoteBox extends StatelessWidget {
  const _QuoteBox({
    super.key,
    required this.q,
    required this.name,
    required this.accent,
    required this.fg,
    required this.background,
    this.onTap,
    this.trailing,
    this.icon,
    this.text,
  });

  final ChatMessage? q;
  final String name;
  final Color accent, fg, background;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Remplace l'aperçu du message (bandeau « Modifier le message »).
  final IconData? icon;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final (snipIcon, snipText) = _snippet(q);
    final md = q?.media;
    final thumb = q != null && !q!.deleted && md != null && md.kind != 3 && md.thumb.isNotEmpty ? md.thumb : null;
    final shownIcon = text == null ? snipIcon : icon;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Material(
        color: background,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (shownIcon != null) ...[
                              Icon(shownIcon, size: 15, color: fg.withValues(alpha: .65)),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                text ?? snipText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13.5, height: 1.25, color: fg.withValues(alpha: .78)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (thumb != null)
                  SizedBox(
                    width: 54,
                    child: md!.kind == 4
                        ? Padding(padding: const EdgeInsets.all(5), child: StickerImage(thumb))
                        : Image.memory(thumb, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Citation dans une bulle : toucher conduit au message cité.
class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({
    required this.id,
    required this.service,
    required this.inMine,
    required this.fg,
    required this.onTap,
  });

  final String id;
  final ChatService service;
  final bool inMine;
  final Color fg;
  final void Function(String id) onTap;

  @override
  Widget build(BuildContext context) {
    final cached = service.byId(id);
    return FutureBuilder<ChatMessage?>(
      initialData: cached,
      future: cached == null ? service.lookup(id) : null,
      builder: (context, snap) {
        final q = snap.data ?? service.byId(id);
        final quotedMine = q?.fromMe ?? false;
        final look = BubbleLook.of(context);
        final onColored = inMine && look.style <= 1;
        return _QuoteBox(
          q: q,
          name: q == null ? '' : (q.fromMe ? 'Toi' : service.partnerLabel),
          accent: _quoteAccent(context, inMine: inMine, quotedMine: quotedMine),
          fg: fg,
          background: onColored ? Colors.black.withValues(alpha: .13) : fg.withValues(alpha: .07),
          onTap: q == null ? null : () => onTap(id),
        );
      },
    );
  }
}

// ===================================================================== saisie

/// Barre de saisie façon WhatsApp : émojis et stickers à gauche, trombone et appareil photo à droite, micro ou envoi.
/// Au-dessus du champ : la réponse en cours, ou le message en cours de modification.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.service,
    required this.controller,
    required this.focus,
    required this.replyTo,
    required this.editing,
    required this.panel,
    required this.onCancelReply,
    required this.onCancelEdit,
    required this.onSend,
    required this.onAttach,
    required this.onCamera,
    required this.onStickers,
    required this.recorder,
    required this.onMic,
    required this.onVoiceSend,
    required this.onVoiceCancel,
  });

  final ChatService service;
  final VoiceRecorder recorder;
  final VoidCallback onMic, onVoiceSend, onVoiceCancel;
  final TextEditingController controller;
  final FocusNode focus;
  final ChatMessage? replyTo, editing;
  final bool panel;
  final VoidCallback onCancelReply, onCancelEdit, onSend, onAttach, onCamera, onStickers;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = controller.text.trim().isEmpty;
    final editing = this.editing;
    final canSend = editing != null || !empty;
    if (recorder.recording) {
      return _RecordingBar(recorder: recorder, onSend: onVoiceSend, onCancel: onVoiceCancel);
    }
    final quoteBg = cs.onSurface.withValues(alpha: .06);
    Widget close(VoidCallback onTap, String tip) => IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.close_rounded, size: 20, color: cs.onSurfaceVariant),
      onPressed: onTap,
      tooltip: tip,
    );
    final banner = editing != null
        ? _QuoteBox(
            key: const ValueKey('edit'),
            q: editing,
            name: 'Modifier le message',
            icon: Icons.edit_outlined,
            text: editing.body.isEmpty ? _snippet(editing).$2 : editing.body,
            accent: cs.primary,
            fg: cs.onSurface,
            background: quoteBg,
            trailing: close(onCancelEdit, 'Annuler la modification'),
          )
        : replyTo != null
        ? _QuoteBox(
            key: ValueKey('reply-${replyTo!.id}'),
            q: replyTo,
            name: replyTo!.fromMe ? 'Toi' : service.partnerLabel,
            accent: _quoteAccent(context, inMine: false, quotedMine: replyTo!.fromMe),
            fg: cs.onSurface,
            background: quoteBg,
            trailing: close(onCancelReply, 'Annuler la réponse'),
          )
        : null;
    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(8, 6, 8, 8 + (panel ? 0 : MediaQuery.paddingOf(context).bottom)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: banner == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(padding: const EdgeInsets.fromLTRB(6, 6, 6, 0), child: banner),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: Icon(
                            panel ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined,
                            key: ValueKey(panel),
                          ),
                        ),
                        tooltip: panel ? 'Clavier' : 'Émojis et stickers',
                        color: cs.onSurfaceVariant,
                        onPressed: editing != null ? null : onStickers,
                      ),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focus,
                          minLines: 1,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          keyboardType: TextInputType.multiline,
                          inputFormatters: [LengthLimitingTextInputFormatter(4000)],
                          style: const TextStyle(fontSize: 16, height: 1.3),
                          decoration: const InputDecoration(
                            hintText: 'Message',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (editing == null) ...[
                        IconButton(
                          icon: Transform.rotate(angle: -.6, child: const Icon(Icons.attach_file_rounded)),
                          tooltip: 'Joindre',
                          color: cs.onSurfaceVariant,
                          visualDensity: VisualDensity.compact,
                          onPressed: onAttach,
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 160),
                          child: empty
                              ? IconButton(
                                  icon: const Icon(Icons.photo_camera_outlined),
                                  tooltip: 'Appareil photo',
                                  color: cs.onSurfaceVariant,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: onCamera,
                                )
                              : const SizedBox(width: 6),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedScale(
            scale: canSend ? 1 : .92,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: Material(
              color: cs.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                // Rien à envoyer : le bouton devient le micro des messages vocaux.
                onTap: canSend ? onSend : onMic,
                child: SizedBox.square(
                  dimension: 48,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Icon(
                      editing != null
                          ? Icons.check_rounded
                          : canSend
                          ? Icons.send_rounded
                          : Icons.mic_rounded,
                      key: ValueKey(editing != null ? 'e' : '$canSend'),
                      color: cs.onPrimary,
                      semanticLabel: editing != null
                          ? 'Enregistrer la modification'
                          : canSend
                          ? 'Envoyer'
                          : 'Enregistrer un message vocal',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================================================================== photos

/// Photo dans la conversation : la miniature d'abord (floutée), puis la photo déchiffrée en mémoire.
class _MediaBubble extends StatelessWidget {
  const _MediaBubble({
    required this.m,
    required this.service,
    required this.radius,
    required this.fg,
    required this.mine,
    required this.night,
    this.quote,
  });

  final ChatMessage m;
  final ChatService service;
  final BorderRadius radius;
  final Color fg;
  final bool mine, night;
  final Widget? quote;

  @override
  Widget build(BuildContext context) {
    final md = m.media!;
    final width = min(MediaQuery.sizeOf(context).width * .68, 280.0);
    final aspect = md.width > 0 && md.height > 0 ? (md.width / md.height).clamp(.62, 1.8) : 1.0;
    final caption = m.body.isNotEmpty;
    return Container(
      width: width,
      padding: const EdgeInsets.all(3),
      decoration: BubbleLook.of(context).box(context, fromMe: mine, radius: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (quote != null) Padding(padding: const EdgeInsets.fromLTRB(2, 2, 2, 3), child: quote),
          ClipRRect(
            borderRadius: BorderRadius.circular(max(0, radius.topLeft.x - 3)),
            child: AspectRatio(
              aspectRatio: aspect,
              child: _Tile(m: m, service: service, showTime: !caption),
            ),
          ),
          if (caption)
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 6, 9, 4),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 8,
                children: [
                  Text(
                    m.body,
                    style: TextStyle(color: fg, fontSize: BubbleLook.of(context).fontSize, height: 1.32),
                  ),
                  _Meta(m: m, color: fg),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Une photo ou vidéo (dans une bulle ou un album) : miniature, état du transfert, durée, heure.
class _Tile extends StatelessWidget {
  const _Tile({required this.m, required this.service, this.showTime = false, this.overlay, this.onTap});

  final ChatMessage m;
  final ChatService service;
  final bool showTime;
  final Widget? overlay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final md = m.media!;
    final mine = m.fromMe;
    final tile = Stack(
      fit: StackFit.expand,
      children: [
        Hero(
          tag: 'photo-${m.id}',
          child: _Photo(m: m, service: service),
        ),
        if (md.kind == 2 && (md.state == 1 || (mine && md.state != 3)))
          Center(
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
            ),
          ),
        if (md.kind == 2)
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_rounded, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(formatDuration(md.durationMs), style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                ],
              ),
            ),
          ),
        if (md.state == 0 || md.state == 2)
          const Center(
            child: SizedBox.square(
              dimension: 30,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            ),
          ),
        if (md.state == 3)
          Container(
            color: Colors.black45,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: const Text(
              'Illisible : altérée en route.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ?overlay,
        if (showTime)
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
              child: _Meta(m: m, color: Colors.white, solid: true),
            ),
          ),
      ],
    );
    if (onTap == null) return tile;
    return GestureDetector(onTap: onTap, child: tile);
  }
}

/// Album : 2 à 4 cases (« +N » au-delà), comme WhatsApp. Toucher une case l'ouvre en grand.
class _AlbumBubble extends StatelessWidget {
  const _AlbumBubble({
    required this.group,
    required this.service,
    required this.radius,
    required this.fg,
    required this.mine,
    this.quote,
  });

  final List<ChatMessage> group;
  final ChatService service;
  final BorderRadius radius;
  final Color fg;
  final bool mine;
  final Widget? quote;

  @override
  Widget build(BuildContext context) {
    final head = group.first;
    final caption = head.body.isNotEmpty;
    final width = min(MediaQuery.sizeOf(context).width * .68, 280.0);
    final inner = width - 6;
    const gap = 2.0;
    final half = (inner - gap) / 2;
    // L'heure et les coches : celles du dernier envoyé ; « en attente » tant que tout n'est pas parti.
    final last = group.last;
    final slowest = group.reduce((a, b) => a.status <= b.status ? a : b);
    final meta = ChatMessage(
      id: last.id,
      fromMe: last.fromMe,
      body: '',
      sentAt: last.sentAt,
      status: slowest.status,
      deleted: false,
      editedAt: head.editedAt,
    );

    void open(ChatMessage x) {
      final md = x.media!;
      if (md.state == 1 || (x.fromMe && md.state != 3)) openMediaViewer(context, service, x);
    }

    Widget tile(int i, {bool time = false}) {
      final x = group[i];
      final more = group.length - 4;
      final plus = i == 3 && more > 0;
      return _Tile(
        m: x,
        service: service,
        onTap: plus ? () => _openAlbum(context, service, group) : () => open(x),
        overlay: plus
            ? Container(
                color: Colors.black45,
                alignment: Alignment.center,
                child: Text(
                  '+$more',
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
                ),
              )
            : null,
      );
    }

    final n = group.length;
    final Widget grid = switch (n) {
      2 => SizedBox(
        height: half,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: tile(0)),
            const SizedBox(width: gap),
            Expanded(child: tile(1)),
          ],
        ),
      ),
      3 => Column(
        children: [
          SizedBox(height: inner * .62, width: inner, child: tile(0)),
          const SizedBox(height: gap),
          SizedBox(
            height: half,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tile(1)),
                const SizedBox(width: gap),
                Expanded(child: tile(2)),
              ],
            ),
          ),
        ],
      ),
      _ => Column(
        children: [
          for (final r in [0, 2]) ...[
            if (r == 2) const SizedBox(height: gap),
            SizedBox(
              height: half,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tile(r)),
                  const SizedBox(width: gap),
                  Expanded(child: tile(r + 1)),
                ],
              ),
            ),
          ],
        ],
      ),
    };

    return Container(
      width: width,
      padding: const EdgeInsets.all(3),
      decoration: BubbleLook.of(context).box(context, fromMe: mine, radius: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (quote != null) Padding(padding: const EdgeInsets.fromLTRB(2, 2, 2, 3), child: quote),
          ClipRRect(
            borderRadius: BorderRadius.circular(max(0, radius.topLeft.x - 3)),
            child: Stack(
              children: [
                grid,
                if (!caption)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
                        child: _Meta(m: meta, color: Colors.white, solid: true),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (caption)
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 6, 9, 4),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 8,
                children: [
                  Text(
                    head.body,
                    style: TextStyle(color: fg, fontSize: BubbleLook.of(context).fontSize, height: 1.32),
                  ),
                  _Meta(m: meta, color: fg),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Tout l'album en grille (depuis la case « +N »).
void _openAlbum(BuildContext context, ChatService service, List<ChatMessage> group) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text('${group.length} photos et vidéos')),
        body: GridView.builder(
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: group.length,
          itemBuilder: (context, i) {
            final x = group[i];
            return _Tile(
              m: x,
              service: service,
              onTap: () {
                final md = x.media!;
                if (md.state == 1 || (x.fromMe && md.state != 3)) openMediaViewer(context, service, x);
              },
            );
          },
        ),
      ),
    ),
  );
}

class _Photo extends StatefulWidget {
  const _Photo({required this.m, required this.service});

  final ChatMessage m;
  final ChatService service;

  @override
  State<_Photo> createState() => _PhotoState();
}

class _PhotoState extends State<_Photo> {
  Future<Uint8List?>? _full;

  bool get _available => widget.m.media!.state == 1 || (widget.m.fromMe && widget.m.media!.state == 0);

  @override
  void didUpdateWidget(_Photo old) {
    super.didUpdateWidget(old);
    if (old.m.media?.state != widget.m.media?.state) _full = null;
  }

  @override
  Widget build(BuildContext context) {
    final thumb = Image.memory(widget.m.media!.thumb, fit: BoxFit.cover, gaplessPlayback: true);
    if (!_available) {
      return ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: thumb);
    }
    // Vidéo : la bulle montre sa miniature ; la vidéo elle-même se lit dans le lecteur.
    if (widget.m.media!.kind == 2) {
      return thumb;
    }
    _full ??= widget.service.photo(widget.m.id);
    return FutureBuilder<Uint8List?>(
      future: _full,
      builder: (context, snap) {
        final b = snap.data;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: b == null
              ? KeyedSubtree(key: const ValueKey('t'), child: thumb)
              : Image.memory(
                  b,
                  key: const ValueKey('f'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: 900,
                  width: double.infinity,
                ),
        );
      },
    );
  }
}

// ===================================================================== stickers

/// Sticker : sans bulle, transparent, avec l'heure dans une petite pastille. La miniature s'affiche aussitôt,
/// puis le sticker entier (animé s'il l'est) une fois téléchargé.
class _StickerBubble extends StatefulWidget {
  const _StickerBubble({required this.m, required this.service, required this.mine, this.quote});

  final ChatMessage m;
  final ChatService service;
  final bool mine;
  final Widget? quote;

  @override
  State<_StickerBubble> createState() => _StickerBubbleState();
}

class _StickerBubbleState extends State<_StickerBubble> {
  Future<Uint8List?>? _full;

  @override
  void didUpdateWidget(_StickerBubble old) {
    super.didUpdateWidget(old);
    if (old.m.media?.state != widget.m.media?.state) _full = null;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final md = m.media!;
    final ready = md.state == 1 || (m.fromMe && md.state == 0);
    if (ready) _full ??= widget.service.photo(m.id);
    final look = BubbleLook.of(context);
    return Column(
      crossAxisAlignment: widget.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.quote != null)
          Container(
            constraints: BoxConstraints(maxWidth: min(MediaQuery.sizeOf(context).width * .68, 280.0)),
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(4),
            decoration: look.box(context, fromMe: widget.mine, radius: BorderRadius.all(look.radius)),
            child: widget.quote,
          ),
        // Comme WhatsApp : un tiers de la largeur de l'écran (160 au plus), l'heure dessous dans une pastille
        // aux couleurs de la bulle.
        SizedBox(
          width: min(MediaQuery.sizeOf(context).width * .34, 160.0),
          // Un sticker large ou haut garde sa forme : pas de vide entre lui et l'heure.
          height:
              min(MediaQuery.sizeOf(context).width * .34, 160.0) *
              (md.width > 0 && md.height > 0 ? (md.height / md.width).clamp(.4, 1.0) : 1.0),
          child: FutureBuilder<Uint8List?>(
            future: _full,
            builder: (context, snap) {
              final b = snap.data ?? (md.thumb.isEmpty ? null : md.thumb);
              if (b == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              return StickerImage(b);
            },
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: look.box(context, fromMe: widget.mine, radius: BorderRadius.circular(10)),
          child: _Meta(m: m, color: look.fg(context, widget.mine)),
        ),
      ],
    );
  }
}

/// Trace d'un message supprimé : ni texte, ni fichier, ni réaction.
class _DeletedBubble extends StatelessWidget {
  const _DeletedBubble({required this.m, required this.groupTop});

  final ChatMessage m;
  final bool groupTop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: groupTop ? 10 : 2),
      child: Align(
        alignment: m.fromMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block_rounded, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                m.fromMe ? 'Tu as supprimé ce message' : 'Message supprimé',
                style: TextStyle(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Text(_time(m.sentAt), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trois points qui sautillent doucement : ton amour est en train d'écrire.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          label: 'Ton amour est en train d\'écrire',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BubbleLook.of(context).box(
              context,
              fromMe: false,
              radius: BorderRadius.only(
                topLeft: BubbleLook.of(context).radius,
                topRight: BubbleLook.of(context).radius,
                bottomRight: BubbleLook.of(context).radius,
                bottomLeft: BubbleLook.of(context).tail,
              ),
            ),
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var k = 0; k < 3; k++)
                    Builder(
                      builder: (_) {
                        final t = ((_c.value - k * .15) % 1.0);
                        final up = t < .3 ? sin(t / .3 * pi) : 0.0;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2.5),
                          width: 7,
                          height: 7,
                          transform: Matrix4.translationValues(0, -3 * up, 0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.onSurface.withValues(alpha: .35 + .5 * up),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================================== messages vocaux

/// Barre d'enregistrement : point rouge qui pulse, durée, onde en direct, annuler ou envoyer.
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({required this.recorder, required this.onSend, required this.onCancel});

  final VoiceRecorder recorder;
  final VoidCallback onSend, onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (recorder.elapsed >= VoiceRecorder.maxDuration) WidgetsBinding.instance.addPostFrameCallback((_) => onSend());

    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(6, 6, 10, 8 + MediaQuery.paddingOf(context).bottom),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: cs.error),
            tooltip: 'Annuler le vocal',
            onPressed: onCancel,
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: .3, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOut,
            builder: (_, v, _) => Opacity(
              opacity: v,
              child: const Icon(Icons.fiber_manual_record_rounded, color: Color(0xFFE5484D), size: 14),
            ),
            onEnd: () {},
          ),
          const SizedBox(width: 6),
          Text(
            formatDuration(recorder.elapsed.inMilliseconds),
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(width: 12),
          // Autant de barres que la place le permet (5 px chacune), les plus récentes à droite.
          Expanded(
            child: SizedBox(
              height: 32,
              child: LayoutBuilder(
                builder: (context, box) {
                  final n = (box.maxWidth / 5).floor();
                  final l = recorder.levels;
                  final recent = l.length > n ? l.sublist(l.length - n) : l;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final v in recent)
                        Container(
                          width: 3,
                          height: 4 + 26 * v,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(color: cs.secondary, borderRadius: BorderRadius.circular(2)),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: cs.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onSend,
              child: SizedBox.square(
                dimension: 48,
                child: Icon(Icons.arrow_upward_rounded, color: cs.onPrimary, semanticLabel: 'Envoyer le vocal'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bulle d'un message vocal : lecture / pause, onde qui se remplit, durée.
class _VoiceBubble extends StatelessWidget {
  const _VoiceBubble({
    required this.m,
    required this.radius,
    required this.fg,
    required this.mine,
    required this.night,
    this.quote,
  });

  final ChatMessage m;
  final BorderRadius radius;
  final Color fg;
  final bool mine, night;
  final Widget? quote;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final md = m.media!;
    final ready = md.state == 1 || (mine && md.state == 0);
    final p = VoicePlayback.instance;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final playing = p.isPlaying(m.id);
        final progress = p.progress(m.id);
        final shown = p.current == m.id ? p.position(m.id).inMilliseconds : md.durationMs;
        return Container(
          width: min(MediaQuery.sizeOf(context).width * .72, 300.0),
          padding: EdgeInsets.fromLTRB(quote == null ? 6 : 4, quote == null ? 6 : 4, quote == null ? 12 : 4, 6),
          decoration: BubbleLook.of(context).box(context, fromMe: mine, radius: radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ?quote,
              Padding(
                padding: EdgeInsets.only(right: quote == null ? 0 : 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: ready ? () => p.toggle(m) : null,
                      icon: ready
                          ? Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: fg, size: 30)
                          : SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
                      tooltip: playing ? 'Pause' : 'Écouter',
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 30,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                for (final (i, v) in md.thumb.indexed)
                                  Expanded(
                                    child: Container(
                                      height: 3 + 24 * v / 255,
                                      margin: const EdgeInsets.symmetric(horizontal: .7),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(2),
                                        color: i / md.thumb.length <= progress && progress > 0
                                            ? (mine ? fg : cs.secondary)
                                            : fg.withValues(alpha: .32),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                formatDuration(shown),
                                style: TextStyle(fontSize: 11.5, color: fg.withValues(alpha: .7)),
                              ),
                              const Spacer(),
                              _Meta(m: m, color: fg),
                            ],
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
      },
    );
  }
}
