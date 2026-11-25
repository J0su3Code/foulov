import 'package:flutter/material.dart';

import '../backup/backup_service.dart';
import '../backup/phrase_screen.dart';
import '../account/danger_screen.dart';
import '../account/links.dart';
import '../account/privacy_screen.dart';
import '../account/report_screen.dart';
import '../lock/app_lock.dart';
import '../../theme/theme_mode.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_service.dart';

/// « Notre espace » : prénoms, surnom, date « ensemble depuis », sécurité.
/// Tout est chiffré de bout en bout ou reste sur ce téléphone : le serveur n'en voit rien.
class SpaceScreen extends StatelessWidget {
  const SpaceScreen({super.key, required this.service, required this.onShowSymbols, required this.onSignOut});

  final ChatService service;
  final VoidCallback onShowSymbols;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([service, AppLock.instance]),
      builder: (context, _) {
        final t = Theme.of(context);
        final cs = t.colorScheme;
        final p = service.profile;
        final lock = AppLock.instance;
        return Scaffold(
          appBar: AppBar(title: const Text('Réglages'), backgroundColor: cs.surface),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              const _Section('Vous deux'),
              _Card(
                children: [
                  _Row(
                    icon: Icons.person_outline_rounded,
                    title: 'Ton prénom',
                    value: p.myName ?? 'À renseigner',
                    hint: 'Ton amour le verra, chiffré de bout en bout.',
                    onTap: () => _editText(
                      context,
                      title: 'Ton prénom',
                      initial: p.myName ?? '',
                      help: 'Envoyé chiffré à ton amour. Le serveur ne le voit pas.',
                      onSave: service.setMyName,
                    ),
                  ),
                  _Row(
                    icon: Icons.favorite_border_rounded,
                    title: 'Comment tu l\'appelles',
                    value: p.partnerNickname ?? p.partnerName ?? 'Ton amour',
                    hint: p.partnerName == null
                        ? 'Surnom visible seulement sur ton téléphone.'
                        : 'Son prénom : ${p.partnerName}. Le surnom reste sur ton téléphone.',
                    onTap: () => _editText(
                      context,
                      title: 'Son surnom',
                      initial: p.partnerNickname ?? '',
                      help: 'Visible seulement sur ton téléphone. Laisse vide pour afficher son prénom.',
                      allowEmpty: true,
                      onSave: service.setPartnerNickname,
                    ),
                  ),
                  _Row(
                    icon: Icons.event_rounded,
                    title: 'Ensemble depuis',
                    value: p.togetherSince == null ? 'À renseigner' : _pretty(p.togetherSince!),
                    hint: 'Partagé avec ton amour, pour compter vos jours ensemble.',
                    onTap: () => _pickDate(context, p.togetherSince),
                  ),
                ],
              ),
              const _Section('Apparence'),
              ValueListenableBuilder(
                valueListenable: ThemeModeSetting.instance,
                builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('Auto'),
                    ),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Jour')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Nuit')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => ThemeModeSetting.instance.set(s.first),
                ),
              ),
              const _Section('Sauvegarde'),
              ListenableBuilder(listenable: BackupService.instance, builder: (context, _) => _BackupCard()),
              const _Section('Confidentialité'),
              _Card(
                children: [
                  ListTile(
                    leading: const Icon(Icons.shield_moon_outlined),
                    title: const Text('Ce que le serveur voit'),
                    subtitle: const Text('Ce qui reste entre vous, ce que nous voyons, et pourquoi.'),
                    trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                    onTap: () => PrivacyScreen.open(context),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.wifi_tethering_rounded),
                    title: const Text('« En ligne » et « écrit… »'),
                    subtitle: const Text(
                      'Montre quand tu es là et quand tu écris (jamais quoi). Désactivé, tu ne vois plus non plus ceux de ton amour.',
                    ),
                    value: service.showActivity,
                    onChanged: service.setShowActivity,
                  ),
                ],
              ),
              const _Section('Sécurité'),
              _Card(
                children: [
                  ListTile(
                    leading: Icon(lock.hasPin ? Icons.pin_rounded : Icons.pin_outlined),
                    title: const Text('Code FouLove'),
                    subtitle: Text(
                      lock.hasPin
                          ? 'Activé : demandé à l\'ouverture et après une minute en arrière-plan.'
                          : '6 chiffres propres à l\'app, même si ton téléphone n\'a pas de verrouillage.',
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                    onTap: () => _pin(context),
                  ),
                  if (lock.supported)
                    SwitchListTile(
                      secondary: const Icon(Icons.fingerprint_rounded),
                      title: const Text('Empreinte ou visage'),
                      subtitle: Text(
                        lock.hasPin
                            ? 'Pour ouvrir plus vite, à la place du code FouLove.'
                            : 'Ouvre FouLove avec l\'empreinte, le visage ou le code du téléphone.',
                      ),
                      value: lock.biometrics,
                      onChanged: lock.setBiometrics,
                    ),
                  ListTile(
                    leading: const Icon(Icons.restore_rounded),
                    title: const Text('Récupérer notre historique'),
                    subtitle: const Text(
                      'Nouveau téléphone sans phrase de récupération : ton amour accepte sur son téléphone, '
                      'et vos échanges arrivent ici, chiffrés.',
                    ),
                    onTap: () async {
                      try {
                        await service.space.requestHistory();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Demande envoyée. Il suffit que ton amour accepte ♡')),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(const SnackBar(content: Text('La demande n\'a pas pu partir. Réessaie.')));
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.sync_rounded),
                    title: const Text('Renvoyer notre espace'),
                    subtitle: const Text(
                      'Si ton amour a changé de téléphone sans sauvegarde : prénoms, photos, dates, albums et tes lettres lui reviennent, chiffrés.',
                    ),
                    onTap: () async {
                      final n = await service.resyncNow();
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(n == 0 ? 'Rien à renvoyer.' : 'Envoyé ($n éléments) ♡')));
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: const Text('Vérifier nos clés'),
                    subtitle: const Text('Échangez vos liens pour être sûrs que personne ne s\'est glissé entre vous.'),
                    onTap: () {
                      Navigator.of(context).pop();
                      onShowSymbols();
                    },
                  ),
                ],
              ),
              const _Section('Aide'),
              _Card(
                children: [
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: const Text('Guide de FouLove'),
                    subtitle: const Text('Tout savoir, pas à pas, sur notre site.'),
                    trailing: Icon(Icons.open_in_new_rounded, size: 20, color: cs.onSurfaceVariant),
                    onTap: () => openLink(context, Links.guide),
                  ),
                  ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Signaler un problème'),
                    subtitle: const Text('Un abus, la sécurité d\'un enfant, un bug.'),
                    trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                    onTap: () => ReportScreen.open(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.gavel_rounded),
                    title: const Text('Conditions d\'utilisation'),
                    trailing: Icon(Icons.open_in_new_rounded, size: 20, color: cs.onSurfaceVariant),
                    onTap: () => openLink(context, Links.terms),
                  ),
                ],
              ),
              const _Section('Zone sensible'),
              _Card(
                children: [
                  ListTile(
                    leading: Icon(Icons.heart_broken_outlined, color: cs.error),
                    title: Text('Fermer notre bulle', style: TextStyle(color: cs.error)),
                    subtitle: const Text('Pour vous deux. Tout est effacé, ton compte reste.'),
                    onTap: () => DangerScreen.open(context, deleteAccount: false, partnerName: service.partnerLabel),
                  ),
                  ListTile(
                    leading: Icon(Icons.delete_forever_rounded, color: cs.error),
                    title: Text('Supprimer mon compte', style: TextStyle(color: cs.error)),
                    subtitle: const Text('Définitif : ton compte, votre bulle et tout son contenu.'),
                    onTap: () => DangerScreen.open(context, deleteAccount: true, partnerName: service.partnerLabel),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                icon: Icon(Icons.logout_rounded, color: cs.error),
                label: Text('Se déconnecter', style: TextStyle(color: cs.error)),
                onPressed: () {
                  Navigator.of(context).pop();
                  onSignOut();
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Vos prénoms, surnoms et dates sont chiffrés sur vos téléphones. Le serveur ne voit que des données illisibles.',
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pin(BuildContext context) async {
    final lock = AppLock.instance;
    if (!lock.hasPin) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PinSetupScreen()));
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Changer le code'),
              onTap: () => Navigator.pop(context, 'change'),
            ),
            ListTile(
              leading: Icon(Icons.lock_open_rounded, color: Theme.of(context).colorScheme.error),
              title: Text('Retirer le code', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    // Toujours le code actuel d'abord : quelqu'un qui tient le téléphone ouvert ne peut pas le changer.
    if (!await askCurrentPin(context) || !context.mounted) return;
    if (action == 'change') {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PinSetupScreen()));
    } else {
      await lock.removePin();
    }
  }

  Future<void> _pickDate(BuildContext context, String? current) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: current == null ? now : DateTime.tryParse(current) ?? now,
      firstDate: DateTime(1950),
      lastDate: now,
      helpText: 'Ensemble depuis le…',
    );
    if (d == null || !context.mounted) return;
    final iso =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await _guard(context, () => service.setTogetherSince(iso));
  }

  Future<void> _editText(
    BuildContext context, {
    required String title,
    required String initial,
    required String help,
    required Future<void> Function(String) onSave,
    bool allowEmpty = false,
  }) async {
    // Le dialogue possède son propre contrôleur : il le libère lui-même, après son animation de fermeture.
    final v = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(title: title, initial: initial, help: help),
    );
    if (v == null || (!allowEmpty && v.trim().isEmpty)) return;
    if (!context.mounted) return;
    await _guard(context, () => onSave(v.trim()));
  }

  Future<void> _guard(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ce changement n\'a pas pu être enregistré.')));
      }
    }
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, required this.help});

  final String title, initial, help;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _c,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        Text(widget.help, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Enregistrer')),
    ],
  );
}

const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String _pretty(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// Nombre de jours ensemble (le premier jour compte pour 1).
int? daysTogether(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  if (d == null) return null;
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays + 1;
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        letterSpacing: .8,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(children: children),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.value, required this.hint, required this.onTap});

  final IconData icon;
  final String title, value, hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(hint),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 130),
      child: Text(
        value,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
      ),
    ),
    onTap: onTap,
  );
}

/// Sauvegarde : activer (phrase de 24 mots), état, sauvegarder maintenant, revoir sa phrase.
class _BackupCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final b = BackupService.instance;
    final cs = Theme.of(context).colorScheme;
    if (!b.enabled) {
      return _Card(
        children: [
          ListTile(
            leading: Icon(Icons.cloud_off_outlined, color: cs.error),
            title: const Text('Sauvegarde désactivée'),
            subtitle: const Text(
              'Si tu perds ce téléphone, vos échanges seraient perdus. Active-la avec une phrase de 24 mots.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: FilledButton.icon(
              icon: const Icon(Icons.shield_outlined),
              label: const Text('Activer la sauvegarde'),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BackupSetupScreen())),
            ),
          ),
        ],
      );
    }
    final last = b.last;
    final ago = last == null ? 'pas encore' : _ago(DateTime.now().difference(last));
    return _Card(
      children: [
        ListTile(
          leading: Icon(Icons.cloud_done_outlined, color: cs.secondary),
          title: const Text('Sauvegarde chiffrée activée'),
          subtitle: Text(
            b.error ??
                (b.running ? 'Sauvegarde en cours…' : 'Dernière sauvegarde : $ago. Chaque jour, automatiquement.'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Sauvegarder maintenant'),
          enabled: !b.running,
          onTap: () async {
            final ok = await b.backupNow(Supabase.instance.client);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ok ? 'Sauvegarde chiffrée terminée.' : 'La sauvegarde n\'a pas abouti.')),
              );
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: const Text('Revoir ma phrase de 24 mots'),
          onTap: () async {
            // Si le verrouillage est possible, on demande d'abord l'empreinte ou le code.
            if (!await AppLock.instance.confirm(
              'Confirme pour afficher ta phrase',
              askPin: () => askCurrentPin(context),
            )) {
              return;
            }
            final p = await b.phrase();
            if (p != null && context.mounted) {
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShowPhraseScreen(phrase: p)));
            }
          },
        ),
      ],
    );
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return 'à l\'instant';
    if (d.inHours < 1) return 'il y a ${d.inMinutes} min';
    if (d.inDays < 1) return 'il y a ${d.inHours} h';
    return 'il y a ${d.inDays} jour${d.inDays > 1 ? 's' : ''}';
  }
}
