import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../src/rust/api/chat.dart';
import '../../theme/foulov_theme.dart';
import '../../ui/love.dart';
import 'chat_service.dart';

/// La conversation du couple : le cœur de l'app.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.service,
    required this.since,
    required this.onShowSymbols,
    required this.onSignOut,
  });

  final ChatService service;

  /// Date de création de l'espace : « Jour N ».
  final DateTime? since;
  final VoidCallback onShowSymbols;
  final VoidCallback onSignOut;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

const _reactions = ['❤️', '🥰', '😂', '😮', '😢', '🔥'];

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  ChatMessage? _replyTo;
  bool _showJump = false;

  /// Messages arrivés pendant que l'écran est ouvert : ils apparaissent avec une animation (une seule fois).
  final Set<String> _entering = {};
  String? _newest;

  ChatService get _s => widget.service;

  @override
  void initState() {
    super.initState();
    _newest = _s.messages.firstOrNull?.id;
    _s.addListener(_changed);
    _s.visible = true;
    _scroll.addListener(_onScroll);
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _s.visible = false;
    _s.removeListener(_changed);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
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
    if (mounted) setState(() {});
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final reply = _replyTo?.id;
    HapticFeedback.lightImpact();
    _input.clear();
    setState(() => _replyTo = null);
    try {
      await _s.send(text, replyTo: reply);
      _toBottom();
    } catch (e) {
      _input.text = text;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ce message n\'a pas pu être préparé. Réessaie.')));
    }
  }

  void _reply(ChatMessage m) {
    HapticFeedback.selectionClick();
    setState(() => _replyTo = m);
    _focus.requestFocus();
  }

  Future<void> _actions(ChatMessage m) async {
    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;
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
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copier'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'reply') _reply(m);
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.body));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copié')));
    }
    if (choice.startsWith('r:')) await _s.react(m.id, choice.substring(2));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final msgs = _s.messages;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(since: widget.since, onShowSymbols: widget.onShowSymbols, onSignOut: widget.onSignOut),
            if (_s.partnerKeyChanged) _KeyChanged(onVerify: widget.onShowSymbols),
            Expanded(
              child: Stack(
                children: [
                  if (msgs.isEmpty)
                    const _Empty()
                  else
                    ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      itemCount: msgs.length + 1,
                      itemBuilder: (context, i) {
                        if (i == msgs.length) return _s.hasMore ? const _Loading() : const _E2EBadge();
                        final m = msgs[i];
                        final older = i + 1 < msgs.length ? msgs[i + 1] : null;
                        final newer = i > 0 ? msgs[i - 1] : null;
                        final newDay = older == null || !_sameDay(older.sentAt, m.sentAt);
                        final groupTop = newDay || older.fromMe != m.fromMe || m.sentAt - older.sentAt > 180000;
                        final groupBottom =
                            newer == null ||
                            newer.fromMe != m.fromMe ||
                            newer.sentAt - m.sentAt > 180000 ||
                            !_sameDay(newer.sentAt, m.sentAt);
                        final bubble = _Bubble(
                          key: ValueKey(m.id),
                          m: m,
                          service: _s,
                          groupTop: groupTop,
                          groupBottom: groupBottom,
                          entering: _entering.remove(m.id),
                          onReply: () => _reply(m),
                          onActions: () => _actions(m),
                          onLove: () => _s.react(m.id, '❤️'),
                        );
                        return newDay ? Column(children: [_DaySeparator(m.sentAt), bubble]) : bubble;
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
            _Composer(
              controller: _input,
              focus: _focus,
              replyTo: _replyTo,
              onCancelReply: () => setState(() => _replyTo = null),
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
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
  const _Header({required this.since, required this.onShowSymbols, required this.onSignOut});

  final DateTime? since;
  final VoidCallback onShowSymbols;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final day = since == null ? null : DateTime.now().difference(since!).inDays + 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outline)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [cs.secondary.withValues(alpha: .35), cs.secondary]),
            ),
            child: const Center(child: Text('💞', style: TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ton amour',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (day != null)
                  Text(
                    day == 1 ? 'Jour 1 de votre jardin' : 'Jour $day de votre jardin',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => v == 'sas' ? onShowSymbols() : onSignOut(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'sas',
                child: ListTile(leading: Icon(Icons.verified_user_outlined), title: Text('Nos 7 symboles')),
              ),
              PopupMenuItem(
                value: 'out',
                child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('Se déconnecter')),
              ),
            ],
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
                  'jusqu\'à ce que vous compariez de nouveau vos 7 symboles.',
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
    return PetalBackground(
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
                    Text('Votre jardin est prêt', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
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
    super.key,
    required this.m,
    required this.service,
    required this.groupTop,
    required this.groupBottom,
    required this.entering,
    required this.onReply,
    required this.onActions,
    required this.onLove,
  });

  final ChatMessage m;
  final ChatService service;
  final bool groupTop, groupBottom, entering;
  final VoidCallback onReply, onActions, onLove;

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
    if (widget.m.myReaction != '❤️') _heart.forward(from: 0);
    widget.onLove();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final night = t.brightness == Brightness.dark;
    final mine = m.fromMe;
    const r = Radius.circular(20), tail = Radius.circular(6);
    // Coin resserré côté expéditeur ; en milieu de groupe, les bulles se « tiennent » par ce côté.
    final radius = BorderRadius.only(
      topLeft: !mine && !widget.groupTop ? tail : r,
      topRight: mine && !widget.groupTop ? tail : r,
      bottomLeft: mine ? r : tail,
      bottomRight: mine ? tail : r,
    );
    final fg = mine ? (night ? const Color(0xFF2A0B16) : cs.onPrimary) : cs.onSurface;
    final reaction = [m.theirReaction, m.myReaction].whereType<String>().toSet();

    Widget bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: mine ? (night ? null : cs.primary) : (night ? FouLovColors.velours2 : cs.surfaceContainer),
        gradient: mine && night ? const LinearGradient(colors: [Color(0xFFFFB08A), Color(0xFFFF7895)]) : null,
        border: mine ? null : Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.replyTo != null) _Quote(id: m.replyTo!, service: widget.service, mine: mine, fg: fg),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(m.body, style: TextStyle(color: fg, fontSize: 15.5, height: 1.32)),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_time(m.sentAt), style: TextStyle(fontSize: 11, color: fg.withValues(alpha: .62))),
                    if (mine) ...[const SizedBox(width: 3), _Status(m.status, fg)],
                  ],
                ),
              ),
            ],
          ),
        ],
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

    final semantics = '${mine ? 'Toi' : 'Ton amour'}, ${_time(m.sentAt)} : ${m.body}';
    Widget row = Semantics(
      label: semantics,
      child: GestureDetector(
        onDoubleTap: _love,
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

class _Status extends StatelessWidget {
  const _Status(this.status, this.fg);

  final int status;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final night = Theme.of(context).brightness == Brightness.dark;
    final (icon, color, label) = switch (status) {
      0 => (Icons.schedule_rounded, fg.withValues(alpha: .55), 'en attente'),
      1 => (Icons.check_rounded, fg.withValues(alpha: .7), 'envoyé'),
      2 => (Icons.done_all_rounded, fg.withValues(alpha: .7), 'distribué'),
      _ => (Icons.done_all_rounded, night ? const Color(0xFF2A0B16) : cs.secondary, 'lu'),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
      child: Icon(icon, key: ValueKey(status), size: 15, color: color, semanticLabel: label),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.id, required this.service, required this.mine, required this.fg});

  final String id;
  final ChatService service;
  final bool mine;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cached = service.byId(id);
    return FutureBuilder<ChatMessage?>(
      initialData: cached,
      future: cached == null ? service.lookup(id) : null,
      builder: (context, snap) {
        final q = snap.data;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
          decoration: BoxDecoration(
            color: fg.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: mine ? fg.withValues(alpha: .6) : cs.secondary, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                q == null ? '' : (q.fromMe ? 'Toi' : 'Ton amour'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg.withValues(alpha: .85)),
              ),
              Text(
                q?.body ?? 'Message introuvable',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: fg.withValues(alpha: .75)),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===================================================================== saisie

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.replyTo,
    required this.onCancelReply,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ChatMessage? replyTo;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canSend = controller.text.trim().isNotEmpty;
    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(10, 6, 10, 8 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: replyTo == null
                ? const SizedBox(width: double.infinity)
                : Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border(left: BorderSide(color: cs.secondary, width: 3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                replyTo!.fromMe ? 'Réponse à toi-même' : 'Réponse à ton amour',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.secondary),
                              ),
                              Text(
                                replyTo!.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: onCancelReply,
                          tooltip: 'Annuler la réponse',
                        ),
                      ],
                    ),
                  ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: cs.outline),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
              ),
              const SizedBox(width: 8),
              AnimatedScale(
                scale: canSend ? 1 : .86,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: Material(
                  color: canSend ? cs.primary : cs.surfaceContainer,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: canSend ? onSend : null,
                    child: SizedBox.square(
                      dimension: 48,
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        color: canSend ? cs.onPrimary : cs.onSurfaceVariant,
                        semanticLabel: 'Envoyer',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
