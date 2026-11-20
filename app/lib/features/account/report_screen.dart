import 'package:flutter/material.dart';

import '../../theme/foulov_theme.dart';
import 'links.dart';

/// « Signaler un problème » : le mécanisme de signalement exigé par les normes de sécurité des enfants
/// (site/src/pages/securite-enfants.md). Les échanges étant chiffrés de bout en bout, rien n'est envoyé
/// automatiquement : la personne écrit elle-même, et choisit ce qu'elle joint.
class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  static void open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReportScreen()));

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(title: const Text('Signaler un problème')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.love.soft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.error.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.emergency_outlined, color: cs.error),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'En cas de danger immédiat, appelle d\'abord les secours : 17 ou 112 (France et Union européenne).',
                    style: TextStyle(height: 1.35, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Que veux-tu nous signaler ?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _Choice(
            icon: Icons.child_care_rounded,
            title: 'La sécurité d\'un enfant',
            subtitle: 'Un contenu ou un comportement qui met un mineur en danger. Traité en priorité.',
            onTap: () => writeToUs(
              context,
              subject: 'Signalement — sécurité des enfants',
              body: _template('Décris la situation (ce qui s\'est passé, quand) :'),
            ),
          ),
          _Choice(
            icon: Icons.report_gmailerrorred_rounded,
            title: 'Un comportement abusif',
            subtitle: 'Harcèlement, menace, chantage, images partagées sans accord, compte utilisé sans consentement.',
            onTap: () => writeToUs(
              context,
              subject: 'Signalement — comportement abusif',
              body: _template('Décris la situation (ce qui s\'est passé, quand) :'),
            ),
          ),
          _Choice(
            icon: Icons.bug_report_outlined,
            title: 'Un bug ou une question',
            subtitle: 'Quelque chose ne marche pas, ou tu as une idée.',
            onTap: () => writeToUs(context, subject: 'FouLove — question', body: _template('Ton message :')),
          ),
          const SizedBox(height: 14),
          Text(
            'Le message part de ton app d\'e-mail vers ${Links.contactEmail}. Comme vos échanges sont chiffrés, '
            'nous ne pouvons pas les voir : si tu veux nous montrer un contenu, joins une capture d\'écran. '
            'Ne nous envoie jamais ta phrase de 24 mots ni ton code FouLove.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            icon: const Icon(Icons.policy_outlined),
            label: const Text('Nos normes de sécurité des enfants'),
            onPressed: () => openLink(context, Links.childSafety),
          ),
        ],
      ),
    );
  }

  static String _template(String prompt) => '$prompt\n\n\n— Envoyé depuis l\'app FouLove';
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: context.cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.cs.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        leading: Icon(icon, color: context.cs.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle)),
        trailing: Icon(Icons.chevron_right_rounded, color: context.cs.onSurfaceVariant),
        onTap: onTap,
      ),
    ),
  );
}
