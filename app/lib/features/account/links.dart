import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Adresses publiques de FouLove (site : dossier `site/` du dépôt). Les mêmes sont données à Google Play.
/// Le jour où le nom de domaine est acheté, seule [siteUrl] change.
abstract final class Links {
  static const siteUrl = 'https://foulove.vercel.app';
  static const guide = '$siteUrl/guide/';
  static const help = '$siteUrl/aide/';
  static const privacyPolicy = '$siteUrl/confidentialite/';
  static const terms = '$siteUrl/conditions/';
  static const childSafety = '$siteUrl/securite-enfants/';
  static const accountDeletion = '$siteUrl/supprimer-mon-compte/';
  static const security = '$siteUrl/securite/';
  static const sourceCode = 'https://github.com/J0su3Code/foulov';
  static const contactEmail = 'josuecode@yahoo.com';
}

/// Ouvre une page dans le navigateur. Si aucun navigateur ne répond, l'adresse est copiée.
Future<void> openLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok) {
    await Clipboard.setData(ClipboardData(text: url));
    messenger?.showSnackBar(SnackBar(content: Text('Adresse copiée : $url')));
  }
}

/// Ouvre un e-mail prérempli vers FouLove. Sans app d'e-mail, l'adresse est copiée.
Future<void> writeToUs(BuildContext context, {required String subject, String body = ''}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = Uri(
    scheme: 'mailto',
    path: Links.contactEmail,
    // `queryParameters` coderait les espaces en « + », que certaines apps d'e-mail affichent tels quels.
    query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
  );
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok) {
    await Clipboard.setData(const ClipboardData(text: Links.contactEmail));
    messenger?.showSnackBar(
      const SnackBar(content: Text('Aucune app d\'e-mail trouvée. Adresse copiée : ${Links.contactEmail}')),
    );
  }
}
