import 'package:flutter/material.dart';

import '../../src/rust/api/device.dart';
import '../../src/rust/api/space.dart';
import '../../theme/foulov_theme.dart';
import '../chat/chat_service.dart';
import '../chat/space_screen.dart';
import '../dates/reminders.dart';
import 'edit_profile_screen.dart';
import 'moments.dart';
import 'story_screen.dart';
import 'widgets.dart';

/// « Nous » : l'accueil, votre profil de couple. Couverture, photo à deux, vos instants, vos jours ensemble,
/// la prochaine date, le dernier mot doux.
class NousScreen extends StatelessWidget {
  const NousScreen({
    super.key,
    required this.chat,
    required this.onOpenChat,
    required this.onOpenLetters,
    required this.onShowSymbols,
    required this.onSignOut,
  });

  final ChatService chat;
  final VoidCallback onOpenChat, onOpenLetters, onShowSymbols, onSignOut;

  @override
  Widget build(BuildContext context) {
    final space = chat.space;
    return ListenableBuilder(
      listenable: Listenable.merge([chat, space]),
      builder: (context, _) {
        final cs = context.cs;
        final top = MediaQuery.paddingOf(context).top;
        final me = chat.profile.myName ?? 'Toi';
        final since = parseIso(chat.profile.togetherSince);
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _Cover(chat: chat, height: 190 + top),
                    Positioned(
                      top: top + 4,
                      right: 4,
                      child: Row(
                        children: [
                          _RoundAction(
                            icon: Icons.edit_outlined,
                            tooltip: 'Modifier notre profil',
                            onTap: () => _push(context, EditProfileScreen(chat: chat)),
                          ),
                          _RoundAction(
                            icon: Icons.settings_outlined,
                            tooltip: 'Réglages',
                            onTap: () => _push(
                              context,
                              SpaceScreen(service: chat, onShowSymbols: onShowSymbols, onSignOut: onSignOut),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 132 + top, 16, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          CoupleAvatar(
                            space: space,
                            size: 84,
                            ring: space.theirsUnseen,
                            onTap: () => space.theirs.isNotEmpty
                                ? openMoments(context, space, mine: false)
                                : _push(context, EditProfileScreen(chat: chat)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: me),
                                    // Une icône, pas le caractère ♥ (que le système dessine en émoji rouge).
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        child: Icon(Icons.favorite_rounded, size: 18, color: cs.primary),
                                      ),
                                    ),
                                    TextSpan(text: chat.partnerLabel),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                sliver: SliverList.list(
                  children: [
                    if (space.bio != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10, left: 2),
                        child: Text('« ${space.bio} »', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14.5)),
                      ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (since != null) ...[
                          LoveChip(
                            icon: Icons.favorite_rounded,
                            label: _togetherLabel(since),
                            onTap: () => _push(context, StoryScreen(chat: chat)),
                          ),
                          LoveChip(muted: true, label: _ymd(since)),
                        ] else
                          LoveChip(
                            icon: Icons.add_rounded,
                            label: 'Depuis quand êtes-vous ensemble ?',
                            onTap: () => _push(context, EditProfileScreen(chat: chat)),
                          ),
                        if ((space.stats?.flameDays ?? 0) > 0)
                          LoveChip(
                            icon: Icons.local_fire_department_rounded,
                            muted: !(space.stats?.flameToday ?? false),
                            label:
                                '${space.stats!.flameDays} ${space.stats!.flameDays == 1 ? 'jour' : 'jours'} de flamme',
                            onTap: () => _flameInfo(context),
                          ),
                      ],
                    ),
                    _HistoryCard(chat: chat),
                    SectionLabel('Vos instants'),
                    _MomentsRow(chat: chat),
                    const SizedBox(height: 18),
                    _NextDate(chat: chat),
                    _LastWord(chat: chat, onTap: onOpenChat),
                    if (space.unreadLetters > 0) ...[
                      const SizedBox(height: 10),
                      LoveCard(
                        onTap: onOpenLetters,
                        child: Row(
                          children: [
                            const GlowIcon(Icons.mail_outline_rounded, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                space.unreadLetters == 1
                                    ? 'Une lettre de ${chat.partnerLabel} t\'attend'
                                    : '${space.unreadLetters} lettres de ${chat.partnerLabel} t\'attendent',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    LoveCard(
                      onTap: () => _push(context, StoryScreen(chat: chat)),
                      child: Row(
                        children: [
                          const GlowIcon(Icons.auto_stories_outlined, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Notre histoire', style: TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  'Votre rencontre, vos anniversaires, vos étapes, vous en chiffres',
                                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
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

  void _flameInfo(BuildContext context) {
    final s = chat.space.stats!;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department_rounded, size: 54, color: context.love.gold),
              const SizedBox(height: 8),
              Text(
                '${s.flameDays} ${s.flameDays == 1 ? 'jour' : 'jours'} de flamme',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                s.flameToday
                    ? 'Vous vous êtes écrit tous les deux aujourd\'hui. La flamme brille !'
                    : 'Écrivez-vous tous les deux avant minuit pour garder votre flamme allumée.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.cs.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 10),
              Text('Votre record : ${s.bestFlame} jours', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

String _togetherLabel(DateTime since) {
  final n = DateTime.now().difference(DateTime(since.year, since.month, since.day)).inDays;
  if (n <= 0) return 'Ensemble depuis aujourd\'hui';
  return 'Ensemble depuis ${frNumber(n)} ${n == 1 ? 'jour' : 'jours'}';
}

/// « 3 ans · 8 mois · 6 jours ».
String _ymd(DateTime since) {
  final now = DateTime.now();
  var y = now.year - since.year, m = now.month - since.month, d = now.day - since.day;
  if (d < 0) {
    m -= 1;
    d += DateTime(now.year, now.month, 0).day;
  }
  if (m < 0) {
    y -= 1;
    m += 12;
  }
  return [
    if (y > 0) '$y ${y == 1 ? 'an' : 'ans'}',
    if (m > 0) '$m mois',
    if (d > 0 || (y == 0 && m == 0)) '$d ${d == 1 ? 'jour' : 'jours'}',
  ].join(' · ');
}

class _Cover extends StatelessWidget {
  const _Cover({required this.chat, required this.height});

  final ChatService chat;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PictureView(
            space: chat.space,
            picture: chat.space.cover,
            fallback: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary, cs.secondary, context.love.gold],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: .28), Colors.transparent, cs.surface],
                stops: const [0, .45, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    icon: Icon(
      icon,
      color: Colors.white,
      shadows: const [Shadow(blurRadius: 8, color: Colors.black38)],
    ),
  );
}

class _MomentsRow extends StatelessWidget {
  const _MomentsRow({required this.chat});

  final ChatService chat;

  @override
  Widget build(BuildContext context) {
    final space = chat.space;
    final cs = context.cs;
    Widget bubble({required Widget child, required String label, required VoidCallback onTap, bool bold = false}) =>
        GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 72,
            child: Column(
              children: [
                child,
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w600 : FontWeight.w400),
                ),
              ],
            ),
          ),
        );
    Widget preview(Moment m, {required bool ring}) => Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ring ? context.love.ring(cs) : null,
        color: ring ? null : cs.outline,
      ),
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface),
        child: ClipOval(
          child: SizedBox.square(
            dimension: 54,
            child: m.kind == 4
                ? DecoratedBox(
                    decoration: BoxDecoration(gradient: LinearGradient(colors: MomentStyles.of(m.style))),
                    child: const Icon(Icons.format_quote_rounded, color: Colors.white),
                  )
                : Image.memory(m.media!.thumb, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        ),
      ),
    );
    final mine = space.mine, theirs = space.theirs;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bubble(
          label: mine.isEmpty ? 'Toi' : 'Toi · ${ago(mine.last.createdAt).replaceFirst('il y a ', '')}',
          onTap: () => mine.isEmpty ? composeMoment(context, space) : openMoments(context, space, mine: true),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (mine.isEmpty)
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.secondary, width: 2),
                    color: context.love.soft,
                  ),
                  child: Icon(Icons.add_rounded, color: cs.primary, size: 28),
                )
              else
                preview(mine.last, ring: false),
              if (mine.isNotEmpty)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: GestureDetector(
                    onTap: () => composeMoment(context, space),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary,
                        border: Border.all(color: cs.surface, width: 2),
                      ),
                      child: Icon(Icons.add_rounded, size: 16, color: cs.onPrimary),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        if (theirs.isNotEmpty)
          bubble(
            label: '${chat.partnerLabel} · ${ago(theirs.last.createdAt).replaceFirst('il y a ', '')}',
            bold: space.theirsUnseen,
            onTap: () => openMoments(context, space, mine: false),
            child: preview(theirs.last, ring: space.theirsUnseen),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              theirs.isEmpty && mine.isEmpty
                  ? 'Partage un instant de ta journée : il disparaît après 24 h.'
                  : 'Visibles 24 h, rien que par vous deux.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.35),
            ),
          ),
        ),
      ],
    );
  }
}

/// Historique entre vos téléphones : sa demande (accepter / refuser), notre demande en attente, l'arrivée, le résultat.
/// Proposé aussi tant que ce téléphone n'a presque rien (nouveau téléphone sans phrase de récupération).
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.chat});

  final ChatService chat;

  @override
  Widget build(BuildContext context) {
    final space = chat.space;
    final h = space.history;
    final name = chat.partnerLabel;
    final cs = context.cs;
    Widget card(IconData icon, String title, String body, {List<Widget> actions = const [], bool busy = false}) =>
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: LoveCard(
            color: Color.lerp(cs.surfaceContainer, context.love.soft, .6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    busy
                        ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                        : Icon(icon, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(body, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.35)),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
                ],
              ],
            ),
          ),
        );
    Future<void> guard(Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Ça n\'a pas marché. Vérifie ta connexion et réessaie.')));
        }
      }
    }

    if (space.historyImported != null) {
      return card(
        Icons.check_circle_rounded,
        'Votre historique est de retour ♡',
        '${space.historyImported} messages retrouvés. Les photos et vidéos se retéléchargent peu à peu.',
        actions: [TextButton(onPressed: space.dismissHistoryImported, child: const Text('Super'))],
      );
    }
    if (h.asked) {
      return FutureBuilder<bool>(
        future: deviceIsVerified(partner: chat.partnerId),
        builder: (context, snap) {
          final verified = snap.data ?? false;
          return card(
            Icons.devices_rounded,
            '$name demande votre historique',
            verified
                ? 'Son nouveau téléphone n\'a pas vos échanges. Si tu acceptes, ils lui sont envoyés chiffrés '
                      '(messages, photos, vidéos, lettres).'
                : 'Vérifiez d\'abord vos clés (symboles ou liens, dans les réglages) : l\'historique ne part que vers '
                      'un téléphone vérifié.',
            actions: [
              TextButton(onPressed: () => guard(space.declineHistory), child: const Text('Refuser')),
              const SizedBox(width: 6),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                onPressed: verified ? () => guard(space.acceptHistory) : null,
                child: const Text('Envoyer'),
              ),
            ],
          );
        },
      );
    }
    if (h.incoming) {
      return card(
        Icons.download_rounded,
        'Votre historique arrive…',
        'Envoyé chiffré par le téléphone de $name. Garde l\'app ouverte quelques instants.',
        busy: true,
      );
    }
    if (h.waiting) {
      return card(
        Icons.hourglass_top_rounded,
        'Demande envoyée',
        '$name doit l\'accepter sur son téléphone. Votre historique arrivera ensuite tout seul.',
        busy: true,
      );
    }
    if (chat.messages.length < 3) {
      return card(
        Icons.restore_rounded,
        'Nouveau téléphone ?',
        'Récupère votre historique depuis le téléphone de $name : il lui suffira d\'accepter.',
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => guard(space.requestHistory),
            child: const Text('Le demander'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class _NextDate extends StatelessWidget {
  const _NextDate({required this.chat});

  final ChatService chat;

  @override
  Widget build(BuildContext context) {
    final list = upcoming(chat.dates, chat.profile.togetherSince, DateTime.now(), birthdays: chat.birthdays);
    if (list.isEmpty) return const SizedBox.shrink();
    final u = list.first;
    final n = u.daysLeft(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LoveCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoryScreen(chat: chat))),
        child: Row(
          children: [
            GlowIcon(u.birthday ? Icons.cake_outlined : Icons.card_giftcard_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${frDate(u.next, weekday: true, year: u.next.year != DateTime.now().year)} · '
                    '${n == 0 ? 'aujourd\'hui' : (n == 1 ? 'demain' : 'dans $n jours')}',
                    style: TextStyle(fontSize: 12.5, color: context.cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            LoveChip(label: n == 0 ? 'Aujourd\'hui ♡' : '$n j'),
          ],
        ),
      ),
    );
  }
}

class _LastWord extends StatelessWidget {
  const _LastWord({required this.chat, required this.onTap});

  final ChatService chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = chat.messages.where((m) => !m.fromMe && !m.deleted).firstOrNull;
    if (m == null) return const SizedBox.shrink();
    final unread = m.status == 0;
    final text = m.body.isNotEmpty
        ? m.body
        : switch (m.media?.kind) {
            1 => '📷 Photo',
            2 => '🎬 Vidéo',
            3 => '🎙️ Message vocal',
            _ => '…',
          };
    return LoveCard(
      onTap: onTap,
      child: Row(
        children: [
          CoupleAvatar(space: chat.space, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chat.partnerLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: unread ? context.cs.onSurface : context.cs.onSurfaceVariant,
                    fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (unread)
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: context.cs.primary, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}
