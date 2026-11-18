import 'package:flutter/material.dart';

import '../../theme/foulov_theme.dart';
import '../chat/chat_service.dart';
import '../dates/dates_screen.dart';
import 'edit_profile_screen.dart';
import 'widgets.dart';

/// Une étape de votre histoire, à partir du jour où tout a commencé.
class Milestone {
  const Milestone(this.label, this.emoji, this.at);

  final String label, emoji;
  final DateTime Function(DateTime since) at;
}

DateTime _days(DateTime s, int n) => DateTime(s.year, s.month, s.day + n);
DateTime _months(DateTime s, int n) => DateTime(s.year, s.month + n, s.day);

final milestones = <Milestone>[
  Milestone('1 semaine', '💕', (s) => _days(s, 7)),
  Milestone('1 mois', '🌹', (s) => _months(s, 1)),
  Milestone('100 jours', '💯', (s) => _days(s, 100)),
  Milestone('6 mois', '💞', (s) => _months(s, 6)),
  Milestone('1 an', '🎉', (s) => _months(s, 12)),
  Milestone('500 jours', '✨', (s) => _days(s, 500)),
  Milestone('2 ans', '💎', (s) => _months(s, 24)),
  Milestone('1 000 jours', '🌟', (s) => _days(s, 1000)),
  Milestone('3 ans', '🥂', (s) => _months(s, 36)),
  Milestone('5 ans', '👑', (s) => _months(s, 60)),
  Milestone('10 ans', '💍', (s) => _months(s, 120)),
  Milestone('20 ans', '🏡', (s) => _months(s, 240)),
  Milestone('25 ans', '🥈', (s) => _months(s, 300)),
  Milestone('50 ans', '🥇', (s) => _months(s, 600)),
];

/// « Notre histoire » : votre rencontre racontée, vos anniversaires, vos étapes, vous en chiffres.
class StoryScreen extends StatelessWidget {
  const StoryScreen({super.key, required this.chat});

  final ChatService chat;

  @override
  Widget build(BuildContext context) {
    final space = chat.space;
    return ListenableBuilder(
      listenable: Listenable.merge([chat, space]),
      builder: (context, _) {
        final cs = context.cs;
        final since = parseIso(chat.profile.togetherSince);
        final stats = space.stats;
        return Scaffold(
          appBar: AppBar(title: const Text('Notre histoire')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              LoveCard(
                onTap: () => _editStory(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Le jour où tout a commencé',
                            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                          ),
                        ),
                        Icon(Icons.edit_outlined, size: 18, color: cs.onSurfaceVariant),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      space.storyTitle ?? (since == null ? 'Racontez votre rencontre' : frDate(since)),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      space.story ??
                          'Où, comment, le premier regard, le premier mot… Écrivez-la à deux : elle reste entre vous.',
                      style: TextStyle(height: 1.5, color: space.story == null ? cs.onSurfaceVariant : cs.onSurface),
                    ),
                  ],
                ),
              ),
              const SectionLabel('Vos anniversaires'),
              Row(
                children: [
                  Expanded(
                    child: _Birthday(
                      name: chat.profile.myName ?? 'Toi',
                      raw: space.myBirthday,
                      empty: 'Ajouter le tien',
                      onTap: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => EditProfileScreen(chat: chat))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Birthday(name: chat.partnerLabel, raw: space.partnerBirthday, empty: 'Pas encore partagé'),
                  ),
                ],
              ),
              if (since != null) ...[const SectionLabel('Vos étapes'), _Milestones(since: since)],
              const SectionLabel('Vous en chiffres'),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.15,
                children: [
                  _Stat(value: stats?.messages ?? 0, label: 'mots doux'),
                  _Stat(value: (stats?.photos ?? 0) + (stats?.videos ?? 0), label: 'souvenirs'),
                  _Stat(value: stats?.voices ?? 0, label: 'vocaux'),
                  _Stat(value: stats?.letters ?? 0, label: 'lettres'),
                  _Stat(value: stats?.bestFlame ?? 0, label: 'jours de flamme (record)'),
                  _Stat(value: since == null ? 0 : DateTime.now().difference(since).inDays, label: 'jours ensemble'),
                ],
              ),
              const SizedBox(height: 18),
              LoveCard(
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DatesScreen(service: chat))),
                child: Row(
                  children: [
                    const GlowIcon(Icons.event_rounded, size: 40),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Toutes vos dates importantes', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editStory(BuildContext context) async {
    final space = chat.space;
    final title = await editText(
      context,
      title: 'Le jour où tout a commencé',
      initial: space.storyTitle ?? '',
      max: 80,
      help: 'Par exemple : « 12 mars 2023, au café du port ».',
    );
    if (title == null || !context.mounted) return;
    final story = await editText(
      context,
      title: 'Votre histoire',
      initial: space.story ?? '',
      max: 4000,
      lines: 6,
      help: 'Partagée par vous deux, chiffrée.',
    );
    if (story == null || !context.mounted) return;
    try {
      await space.set('story_title', title);
      await space.set('story', story);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Votre histoire n\'a pas pu être enregistrée.')));
      }
    }
  }
}

class _Birthday extends StatelessWidget {
  const _Birthday({required this.name, required this.raw, required this.empty, this.onTap});

  final String name, empty;
  final String? raw;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = parseBirthday(raw);
    String? detail;
    if (b != null) {
      final next = nextDay(b.$1, b.$2);
      final n = daysUntil(next);
      final age = b.$3 == null ? null : next.year - b.$3!;
      detail =
          '${b.$2} ${monthsShort[b.$1 - 1]}${age == null ? '' : ' · $age ans'}\n'
          '${n == 0 ? 'Aujourd\'hui ! 🎂' : 'dans $n ${n == 1 ? 'jour' : 'jours'}'}';
    }
    return LoveCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.cake_outlined, color: context.cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(detail ?? empty, style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Milestones extends StatelessWidget {
  const _Milestones({required this.since});

  final DateTime since;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final reached = milestones.where((m) => !m.at(since).isAfter(now)).toList();
    final next = milestones.where((m) => m.at(since).isAfter(now)).firstOrNull;
    // Les étapes atteintes, puis la prochaine (grisée).
    final shown = [...reached.reversed.take(4).toList().reversed, ?next];
    double progress = 1;
    if (next != null) {
      final from = reached.isEmpty ? since : reached.last.at(since);
      final to = next.at(since);
      progress = now.difference(from).inMinutes / to.difference(from).inMinutes;
    }
    return LoveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final m in shown)
                Expanded(
                  child: Opacity(
                    opacity: m == next ? .38 : 1,
                    child: Column(
                      children: [
                        Text(m.emoji, style: const TextStyle(fontSize: 26)),
                        const SizedBox(height: 4),
                        Text(m.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 6,
                backgroundColor: context.love.surface2,
                valueColor: AlwaysStoppedAnimation(context.cs.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Prochaine étape : ${next.label}, le ${frDate(next.at(since))} '
              '(dans ${daysUntil(next.at(since))} jours)',
              style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Toutes les étapes franchies. Quelle histoire ! ♡',
                style: TextStyle(color: context.cs.primary),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => LoveCard(
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          child: Text(
            frNumber(value),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: context.cs.primary),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant, height: 1.2),
        ),
      ],
    ),
  );
}
