import 'package:flutter/material.dart';

import '../lock/app_lock.dart';
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
          appBar: AppBar(title: const Text('Notre espace'), backgroundColor: cs.surface),
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
              const _Section('Confidentialité'),
              _Card(
                children: [
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
                  if (lock.supported)
                    SwitchListTile(
                      secondary: Icon(lock.enabled ? Icons.lock_rounded : Icons.lock_open_rounded),
                      title: const Text('Verrouillage de l\'app'),
                      subtitle: const Text('Empreinte, visage ou code du téléphone, à l\'ouverture.'),
                      value: lock.enabled,
                      onChanged: lock.setEnabled,
                    )
                  else
                    const ListTile(
                      leading: Icon(Icons.lock_open_rounded),
                      title: Text('Verrouillage indisponible'),
                      subtitle: Text(
                        'Active d\'abord un code, une empreinte ou le visage dans les réglages de ton téléphone.',
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: const Text('Nos 7 symboles'),
                    subtitle: const Text('Pour vérifier ensemble que personne ne s\'est glissé entre vous.'),
                    onTap: () {
                      Navigator.of(context).pop();
                      onShowSymbols();
                    },
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
