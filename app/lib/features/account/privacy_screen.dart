import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/foulov_theme.dart';

/// Adresse publique de la politique de confidentialité (aussi donnée à Google Play).
const privacyPolicyUrl = 'https://github.com/J0su3Code/foulov/blob/main/docs/CONFIDENTIALITE.md';
const accountDeletionUrl = 'https://github.com/J0su3Code/foulov/blob/main/docs/SUPPRESSION-COMPTE.md';
const sourceCodeUrl = 'https://github.com/J0su3Code/foulov';

/// « Ce que le serveur voit » : ce qui reste entre vous, ce qui est visible et pourquoi, ce que nous ne faisons pas.
/// Le même contenu que docs/CONFIDENTIALITE.md, en version courte.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static void open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()));

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(title: const Text('Ce que le serveur voit')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _Hero(),
          const _Title('Ce qui reste entre vous deux', icon: Icons.lock_rounded),
          const _Card(
            children: [
              _Line(Icons.chat_bubble_outline_rounded, 'Vos messages, réactions, réponses et vocaux'),
              _Line(Icons.photo_outlined, 'Vos photos, vidéos et leurs légendes'),
              _Line(Icons.auto_awesome_outlined, 'Vos instants, lettres et capsules'),
              _Line(Icons.favorite_border_rounded, 'Prénoms, surnoms, bio, votre histoire, anniversaires, dates'),
              _Line(Icons.palette_outlined, 'Photo à deux, couverture, fond, couleurs, albums'),
              _Line(Icons.cloud_outlined, 'Votre sauvegarde (clé tirée de vos 24 mots)'),
            ],
            footer:
                'Chiffrés sur ton téléphone avant de partir, déchiffrés seulement sur celui de ton amour. '
                'Nos serveurs ne transportent que des données illisibles. Nous n\'avons pas les clés.',
          ),
          const _Title('Ce que nos serveurs voient', icon: Icons.visibility_outlined),
          const _Card(
            children: [
              _Seen('Ton adresse e-mail (ou ton compte Google ou Apple)', 'pour te connecter'),
              _Seen('Que vos deux comptes forment un couple', 'pour acheminer vos messages'),
              _Seen('L\'heure d\'envoi et le nombre de contenus chiffrés', 'pour les acheminer dans l\'ordre'),
              _Seen('Leur taille approximative (arrondie)', 'pour les stocker'),
              _Seen('Le jeton de notification de ton téléphone', 'pour te prévenir (texte fixe, sans contenu)'),
              _Seen('Quand tu as l\'app ouverte, quand tu écris', 'désactivable dans les réglages'),
              _Seen('Les clés publiques de ton téléphone', 'pour permettre le chiffrement'),
              _Seen('Ton adresse IP, dans les journaux de nos hébergeurs', 'fonctionnement du réseau'),
            ],
          ),
          const _Title('Ce que nous ne faisons pas', icon: Icons.block_rounded),
          const _Card(
            children: [
              _Line(Icons.check_rounded, 'Aucune publicité'),
              _Line(Icons.check_rounded, 'Aucune revente ni partage de vos données'),
              _Line(Icons.check_rounded, 'Aucune mesure d\'audience, aucun traceur'),
              _Line(Icons.check_rounded, 'Aucune lecture de vos échanges : techniquement impossible'),
            ],
          ),
          const _Title('Nos hébergeurs', icon: Icons.dns_outlined),
          const _Card(
            children: [
              _Seen('Supabase', 'comptes et acheminement · Union européenne (Francfort)'),
              _Seen('Cloudflare R2', 'fichiers chiffrés'),
              _Seen('Google Firebase', 'notifications, sans contenu'),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: const Text('Politique de confidentialité complète'),
            onPressed: () => launchUrl(Uri.parse(privacyPolicyUrl), mode: LaunchMode.externalApplication),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            icon: const Icon(Icons.code_rounded),
            label: const Text('Vérifier le code (il est public)'),
            onPressed: () => launchUrl(Uri.parse(sourceCodeUrl), mode: LaunchMode.externalApplication),
          ),
          const SizedBox(height: 8),
          Text(
            'Si vous perdez vos deux téléphones sans votre phrase de récupération, vos échanges sont perdus : personne '
            'ne peut les récupérer, pas même nous. C\'est le prix d\'une vraie confidentialité.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: LinearGradient(colors: [context.love.soft, context.cs.surfaceContainer]),
      border: Border.all(color: context.cs.outline),
    ),
    child: Row(
      children: [
        Icon(Icons.shield_moon_outlined, size: 40, color: context.cs.primary),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            'FouLove est faite pour que personne d\'autre que vous deux ne puisse lire ce que vous partagez. '
            'Pas même nous. Voici exactement ce que nous voyons, et pourquoi.',
            style: TextStyle(height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _Title extends StatelessWidget {
  const _Title(this.text, {required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Row(
      children: [
        Icon(icon, size: 18, color: context.cs.primary),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.footer});

  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
    decoration: BoxDecoration(
      color: context.cs.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.cs.outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...children,
        if (footer != null) ...[
          const SizedBox(height: 6),
          Text(footer!, style: TextStyle(fontSize: 12.5, color: context.cs.onSurfaceVariant, height: 1.4)),
        ],
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 19, color: context.cs.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.3))),
      ],
    ),
  );
}

class _Seen extends StatelessWidget {
  const _Seen(this.what, this.why);

  final String what, why;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(what, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3)),
        Text(why, style: TextStyle(fontSize: 12.5, color: context.cs.onSurfaceVariant)),
      ],
    ),
  );
}
