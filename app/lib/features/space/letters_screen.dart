import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../src/rust/api/space.dart';
import '../../theme/foulov_theme.dart';
import '../../ui/love.dart';
import '../chat/chat_service.dart';
import 'widgets.dart';

/// « Lettres » : des mots longs, à lire au calme, et des capsules qui ne s'ouvrent qu'au jour choisi.
class LettersScreen extends StatelessWidget {
  const LettersScreen({super.key, required this.chat});

  final ChatService chat;

  @override
  Widget build(BuildContext context) {
    final space = chat.space;
    return ListenableBuilder(
      listenable: space,
      builder: (context, _) {
        final t = Theme.of(context);
        final letters = space.letters;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Lettres',
                            style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(64, 42)),
                          onPressed: () => _write(context),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Écrire'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (letters.isEmpty)
                  SliverFillRemaining(hasScrollBody: false, child: _Empty(onWrite: () => _write(context)))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                    sliver: SliverList.separated(
                      itemCount: letters.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _LetterTile(chat: chat, l: letters[i]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _write(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => WriteLetter(chat: chat)));
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onWrite});

  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const BeatingHeart(size: 60),
        const SizedBox(height: 18),
        Text(
          'Les mots qui comptent',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Une lettre, c\'est plus qu\'un message : on la prend, on la garde. '
          'Et une capsule ne s\'ouvre qu\'au jour que tu choisis.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.cs.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 18),
        FilledButton(onPressed: onWrite, child: const Text('Écrire ma première lettre')),
      ],
    ),
  );
}

class _LetterTile extends StatelessWidget {
  const _LetterTile({required this.chat, required this.l});

  final ChatService chat;
  final Letter l;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final fresh = !l.fromMe && !l.sealed && l.readAt == null;
    final sent = DateTime.fromMillisecondsSinceEpoch(l.sentAt);
    final who = l.fromMe ? 'de toi' : 'de ${chat.partnerLabel}';
    String sub;
    if (l.sealed) {
      sub = '$who · s\'ouvrira le ${frDate(DateTime.fromMillisecondsSinceEpoch(l.openAt!))}';
    } else if (l.fromMe) {
      sub =
          '$who · ${l.readAt != null ? 'lue par ${chat.partnerLabel}' : 'pas encore lue'} · ${frDate(sent, year: sent.year != DateTime.now().year)}';
    } else {
      sub = '$who · ${frDate(sent, year: sent.year != DateTime.now().year)}';
    }
    Widget body = Row(
      children: [
        l.sealed
            ? const GlowIcon(Icons.lock_outline_rounded, size: 40)
            : Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: context.love.soft, borderRadius: BorderRadius.circular(13)),
                child: Icon(l.fromMe ? Icons.outbox_outlined : Icons.mail_outline_rounded, color: cs.primary),
              ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.sealed && !l.fromMe ? 'Capsule de ${chat.partnerLabel}' : l.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: fresh ? FontWeight.w800 : FontWeight.w600, fontSize: 15),
              ),
              Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        if (fresh) LoveChip(label: 'Nouvelle'),
        if (l.starred) Icon(Icons.star_rounded, color: context.love.gold),
      ],
    );
    if (l.sealed) {
      final open = DateTime.fromMillisecondsSinceEpoch(l.openAt!);
      final total = open.difference(sent).inMinutes;
      final done = DateTime.now().difference(sent).inMinutes;
      final left = daysUntil(open);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          body,
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total <= 0 ? 1 : (done / total).clamp(0, 1),
              minHeight: 5,
              backgroundColor: context.love.surface2,
              valueColor: AlwaysStoppedAnimation(context.love.gold),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            left <= 0
                ? 'S\'ouvre aujourd\'hui, dans quelques heures.'
                : 'Encore $left ${left == 1 ? 'jour' : 'jours'}. Scellée jusque-là, chez vous deux.',
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),
        ],
      );
    }
    return LoveCard(
      color: fresh ? Color.lerp(cs.surfaceContainer, context.love.soft, .7) : null,
      onTap: () {
        if (l.sealed) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Patience ♡ Elle s\'ouvrira le ${frDate(DateTime.fromMillisecondsSinceEpoch(l.openAt!), weekday: true)}.',
                ),
              ),
            );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReadLetter(chat: chat, id: l.id),
          ),
        );
      },
      child: body,
    );
  }
}

// ===================================================================== écrire

class WriteLetter extends StatefulWidget {
  const WriteLetter({super.key, required this.chat});

  final ChatService chat;

  @override
  State<WriteLetter> createState() => _WriteLetterState();
}

class _WriteLetterState extends State<WriteLetter> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  DateTime? _openAt;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _ready => _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty && !_busy;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _openAt ?? now.add(const Duration(days: 30)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: DateTime(now.year + 30),
      helpText: 'À ouvrir le…',
    );
    if (d == null || !mounted) return;
    // Ouverture le matin du jour choisi, à 8 h.
    setState(() => _openAt = DateTime(d.year, d.month, d.day, 8));
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await widget.chat.space.sendLetter(_title.text, _body.text, openAt: _openAt);
      HapticFeedback.lightImpact();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _openAt == null
                ? 'Lettre envoyée à ${widget.chat.partnerLabel} ♡'
                : 'Capsule scellée jusqu\'au ${frDate(_openAt!)} ♡',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('La lettre n\'a pas pu être préparée.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(
        title: Text(_openAt == null ? 'Une lettre' : 'Une capsule'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
              onPressed: _ready ? _send : null,
              child: Text(_busy ? 'Envoi…' : (_openAt == null ? 'Envoyer' : 'Sceller')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [cs.surfaceContainer, context.love.surface2],
              ),
              border: Border.all(color: cs.outline),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  maxLength: 80,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  decoration: const InputDecoration(
                    hintText: 'Un titre',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    counterText: '',
                  ),
                ),
                TextField(
                  controller: _body,
                  minLines: 12,
                  maxLines: null,
                  maxLength: 30000,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 16, height: 1.6),
                  decoration: InputDecoration(
                    hintText: 'Mon cœur,\n\n…',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    counterText: '',
                    hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: .7)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LoveCard(
            onTap: _openAt == null ? _pickDate : null,
            child: Row(
              children: [
                const GlowIcon(Icons.hourglass_bottom_rounded, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _openAt == null ? 'En faire une capsule' : 'S\'ouvrira le ${frDate(_openAt!, weekday: true)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _openAt == null
                            ? 'Elle arrive tout de suite, mais reste scellée jusqu\'au jour choisi.'
                            : 'Ni ${widget.chat.partnerLabel} ni toi ne pourrez la relire avant.',
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (_openAt != null)
                  IconButton(
                    tooltip: 'Envoyer tout de suite',
                    onPressed: () => setState(() => _openAt = null),
                    icon: const Icon(Icons.close_rounded),
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
          if (_openAt != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _pickDate, child: const Text('Changer la date')),
            ),
        ],
      ),
    );
  }
}

// ===================================================================== lire

class ReadLetter extends StatefulWidget {
  const ReadLetter({super.key, required this.chat, required this.id});

  final ChatService chat;
  final String id;

  @override
  State<ReadLetter> createState() => _ReadLetterState();
}

class _ReadLetterState extends State<ReadLetter> {
  @override
  void initState() {
    super.initState();
    final l = widget.chat.space.letters.where((x) => x.id == widget.id).firstOrNull;
    if (l != null) widget.chat.space.readLetter(l);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.chat.space,
    builder: (context, _) {
      final l = widget.chat.space.letters.where((x) => x.id == widget.id).firstOrNull;
      final cs = context.cs;
      if (l == null) return const Scaffold();
      final sent = DateTime.fromMillisecondsSinceEpoch(l.sentAt);
      return Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: l.starred ? 'Retirer des préférées' : 'Lettre préférée',
              onPressed: () => widget.chat.space.starLetter(l, !l.starred),
              icon: Icon(l.starred ? Icons.star_rounded : Icons.star_outline_rounded, color: context.love.gold),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [cs.surfaceContainer, context.love.surface2],
                ),
                border: Border.all(color: cs.outline),
                boxShadow: [
                  BoxShadow(color: cs.primary.withValues(alpha: .10), blurRadius: 30, offset: const Offset(0, 12)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l.fromMe ? 'De toi' : 'De ${widget.chat.partnerLabel}'} · ${frDate(sent)}',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(l.body, style: const TextStyle(fontSize: 16.5, height: 1.65)),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Icon(Icons.favorite_rounded, color: cs.primary),
                  ),
                ],
              ),
            ),
            if (l.fromMe)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  l.readAt != null
                      ? 'Lue par ${widget.chat.partnerLabel} le ${frDate(DateTime.fromMillisecondsSinceEpoch(l.readAt!))}'
                      : 'Pas encore lue',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                ),
              ),
          ],
        ),
      );
    },
  );
}
