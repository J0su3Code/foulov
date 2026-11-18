import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/foulov_theme.dart';
import '../chat/chat_service.dart';
import 'crop.dart';
import 'widgets.dart';

/// Modifier le profil du couple : photo à deux, couverture, prénoms, bio, date de rencontre, ton anniversaire.
/// Tout part chiffré chez l'autre, sauf le surnom que tu lui donnes, qui reste sur ce téléphone.
class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key, required this.chat});

  final ChatService chat;

  @override
  Widget build(BuildContext context) {
    final space = chat.space;
    return ListenableBuilder(
      listenable: Listenable.merge([chat, space]),
      builder: (context, _) {
        final cs = context.cs;
        final p = chat.profile;
        final bday = parseBirthday(space.myBirthday);
        return Scaffold(
          appBar: AppBar(title: const Text('Notre profil')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              // Couverture et photo à deux, telles qu'elles apparaissent sur l'accueil.
              SizedBox(
                height: 200,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: () => _pickPicture(context, 'cover'),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          height: 150,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PictureView(
                                space: space,
                                picture: space.cover,
                                fallback: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [cs.primary, cs.secondary, context.love.gold]),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: _Badge(icon: Icons.photo_camera_outlined, label: 'Couverture'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      bottom: 0,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CoupleAvatar(space: space, size: 88, onTap: () => _pickPicture(context, 'avatar')),
                          Positioned(
                            right: 0,
                            bottom: 4,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: cs.surface, width: 2),
                                ),
                                child: Icon(Icons.photo_camera_rounded, size: 16, color: cs.onPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Text(
                  'Une seule photo à deux et une couverture, partagées entre vos téléphones, chiffrées.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ),
              const SectionLabel('Vous deux'),
              _Field(
                icon: Icons.person_outline_rounded,
                title: 'Ton prénom',
                value: p.myName,
                placeholder: 'À renseigner',
                onTap: () => _text(
                  context,
                  title: 'Ton prénom',
                  initial: p.myName ?? '',
                  max: 40,
                  help: 'Envoyé chiffré à ${chat.partnerLabel}.',
                  save: chat.setMyName,
                ),
              ),
              _Field(
                icon: Icons.favorite_border_rounded,
                title: 'Comment tu l\'appelles',
                value: p.partnerNickname ?? p.partnerName,
                placeholder: 'Ton amour',
                hint: 'Surnom visible seulement sur ton téléphone.',
                onTap: () => _text(
                  context,
                  title: 'Son surnom',
                  initial: p.partnerNickname ?? '',
                  max: 40,
                  allowEmpty: true,
                  help: p.partnerName == null
                      ? 'Visible seulement sur ton téléphone.'
                      : 'Son prénom : ${p.partnerName}. Laisse vide pour l\'afficher.',
                  save: chat.setPartnerNickname,
                ),
              ),
              _Field(
                icon: Icons.format_quote_rounded,
                title: 'Votre bio',
                value: space.bio,
                placeholder: 'Une phrase qui vous ressemble',
                onTap: () => _text(
                  context,
                  title: 'Votre bio',
                  initial: space.bio ?? '',
                  max: 160,
                  allowEmpty: true,
                  help: 'Partagée par vous deux, chiffrée.',
                  save: (v) => space.set('bio', v),
                ),
              ),
              _Field(
                icon: Icons.favorite_rounded,
                title: 'Ensemble depuis',
                value: p.togetherSince == null ? null : frDate(DateTime.parse(p.togetherSince!)),
                placeholder: 'Le jour où tout a commencé',
                onTap: () => _pickTogether(context),
              ),
              const SectionLabel('Toi'),
              _Field(
                icon: Icons.cake_outlined,
                title: 'Ton anniversaire',
                value: bday == null
                    ? null
                    : '${bday.$2} ${monthsLong[bday.$1 - 1]}${bday.$3 == null ? '' : ' ${bday.$3}'}',
                placeholder: 'Pour que ${chat.partnerLabel} ne l\'oublie jamais',
                onTap: () => _pickBirthday(context),
              ),
              if (space.myBirthday != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _guard(context, () => space.set('birthday', '', personal: true)),
                    child: const Text('Retirer mon anniversaire'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickPicture(BuildContext context, String slot) async {
    final space = chat.space;
    final has = slot == 'avatar' ? space.avatar != null : space.cover != null;
    String? action = 'pick';
    if (has) {
      action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choisir une autre photo'),
                onTap: () => Navigator.pop(context, 'pick'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: context.cs.error),
                title: Text('Retirer la photo', style: TextStyle(color: context.cs.error)),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }
    if (action == null || !context.mounted) return;
    if (action == 'remove') {
      await _guard(context, () => space.removePicture(slot));
      return;
    }
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    if (f == null || !context.mounted) return;
    final cropped = await cropFor(context, slot, f.path);
    if (cropped == null || !context.mounted) return;
    await _guard(context, () => space.setPicture(slot, cropped));
  }

  Future<void> _pickTogether(BuildContext context) async {
    final now = DateTime.now();
    final cur = parseIso(chat.profile.togetherSince);
    final d = await showDatePicker(
      context: context,
      initialDate: cur ?? now,
      firstDate: DateTime(1950),
      lastDate: now,
      helpText: 'Ensemble depuis le…',
    );
    if (d == null || !context.mounted) return;
    await _guard(context, () => chat.setTogetherSince(_iso(d)));
  }

  Future<void> _pickBirthday(BuildContext context) async {
    final cur = parseBirthday(chat.space.myBirthday);
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: cur == null ? DateTime(now.year - 25, now.month, now.day) : DateTime(cur.$3 ?? 2000, cur.$1, cur.$2),
      firstDate: DateTime(1920),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.input,
      helpText: 'Ta date de naissance',
    );
    if (d == null || !context.mounted) return;
    // L'année reste facultative : certains préfèrent ne partager que le jour.
    final withYear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Partager ton année ?'),
        content: Text('${chat.partnerLabel} verra ton âge, ou seulement le jour et le mois.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Jour et mois')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Avec l\'année')),
        ],
      ),
    );
    if (withYear == null || !context.mounted) return;
    final mmdd = '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await _guard(context, () => chat.space.set('birthday', withYear ? _iso(d) : mmdd, personal: true));
  }
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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

Future<void> _text(
  BuildContext context, {
  required String title,
  required String initial,
  required int max,
  required String help,
  required Future<void> Function(String) save,
  bool allowEmpty = false,
}) async {
  final v = await editText(context, title: title, initial: initial, max: max, help: help);
  if (v == null || (!allowEmpty && v.trim().isEmpty) || !context.mounted) return;
  await _guard(context, () => save(v.trim()));
}

/// Dialogue de saisie (une ligne, ou plusieurs avec `lines`). Renvoie `null` si annulé.
Future<String?> editText(
  BuildContext context, {
  required String title,
  required String initial,
  required int max,
  String? help,
  int lines = 1,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(title: title, initial: initial, max: max, help: help, lines: lines),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, required this.max, this.help, this.lines = 1});

  final String title, initial;
  final String? help;
  final int max, lines;

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
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _c,
            autofocus: true,
            maxLength: widget.max,
            minLines: widget.lines,
            maxLines: widget.lines == 1 ? 1 : 12,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: widget.lines == 1 ? (v) => Navigator.pop(context, v) : null,
          ),
          if (widget.help != null)
            Text(widget.help!, style: TextStyle(fontSize: 12.5, color: context.cs.onSurfaceVariant)),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      TextButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Enregistrer')),
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.icon,
    required this.title,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.hint,
  });

  final IconData icon;
  final String title, placeholder;
  final String? value, hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: LoveCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: context.cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12.5, color: context.cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(
                  value ?? placeholder,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
                    color: value == null ? context.cs.onSurfaceVariant : context.cs.onSurface,
                  ),
                ),
                if (hint != null) Text(hint!, style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.cs.onSurfaceVariant),
        ],
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.white),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
