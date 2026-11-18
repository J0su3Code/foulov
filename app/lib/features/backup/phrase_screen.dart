import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../src/rust/api/backup.dart';
import 'backup_service.dart';

/// Écran sensible : pas de capture d'écran ni d'aperçu dans les apps récentes (Android).
Future<void> _secure(bool on) async {
  if (!Platform.isAndroid) return;
  try {
    await const MethodChannel('foulove/notifications').invokeMethod<void>('secure', on);
  } catch (_) {}
}

/// Activer la sauvegarde : comprendre, noter ses 24 mots, vérifier 3 d'entre eux.
class BackupSetupScreen extends StatefulWidget {
  const BackupSetupScreen({super.key});

  @override
  State<BackupSetupScreen> createState() => _BackupSetupScreenState();
}

class _BackupSetupScreenState extends State<BackupSetupScreen> {
  late final NewPhrase _p = backupNewPhrase();
  late final List<String> _words = _p.phrase.split(' ');
  late final List<int> _ask = (List.generate(24, (i) => i)..shuffle(Random.secure())).take(3).toList()..sort();
  final _answers = List.generate(3, (_) => TextEditingController());
  int _step = 0;
  bool _saving = false;
  String? _wrong;

  @override
  void initState() {
    super.initState();
    _secure(true);
  }

  @override
  void dispose() {
    _secure(false);
    for (final c in _answers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _check() async {
    // Accents facultatifs : les 2048 mots restent distincts sans eux.
    final ok = [
      for (var i = 0; i < 3; i++)
        backupPlainWord(word: _answers[i].text.trim()) == backupPlainWord(word: _words[_ask[i]]),
    ].every((x) => x);
    if (!ok) {
      setState(() => _wrong = 'Un des mots ne correspond pas. Vérifie ton papier : le numéro compte.');
      return;
    }
    setState(() => _saving = true);
    await BackupService.instance.enable(Uint8List.fromList(_p.secret), Supabase.instance.client);
    if (mounted) setState(() => _step = 3);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final title = t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700);
    final soft = t.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant, height: 1.4);
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde'), backgroundColor: cs.surface),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: switch (_step) {
            0 => [
              Text('Ta phrase de récupération', style: title),
              const SizedBox(height: 12),
              Text(
                'Tes messages, photos et dates sont chiffrés sur ce téléphone. Pour les retrouver si tu le perds ou '
                'en changes, FouLove en garde une copie chiffrée avec une clé que toi seul possèdes : 24 mots.',
                style: soft,
              ),
              const SizedBox(height: 16),
              _Point(
                icon: Icons.edit_note_rounded,
                text: 'Note-les sur papier, dans l\'ordre, et range-le en lieu sûr.',
              ),
              _Point(
                icon: Icons.no_photography_outlined,
                text: 'Pas de capture d\'écran, pas de photo, ne les envoie à personne.',
              ),
              _Point(
                icon: Icons.lock_outline_rounded,
                text:
                    'Sans ces mots, personne ne peut lire la sauvegarde, pas même nous. Perdus, ils ne se retrouvent pas.',
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => setState(() => _step = 1), child: const Text('Afficher mes 24 mots')),
            ],
            1 => [
              Text('Note tes 24 mots', style: title),
              const SizedBox(height: 8),
              Text('Dans l\'ordre, avec leur numéro.', style: soft),
              const SizedBox(height: 18),
              _Words(words: _words),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => setState(() => _step = 2), child: const Text('Je les ai notés')),
            ],
            2 => [
              Text('Vérifions', style: title),
              const SizedBox(height: 8),
              Text('Recopie ces trois mots depuis ton papier.', style: soft),
              const SizedBox(height: 18),
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _answers[i],
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(labelText: 'Mot n° ${_ask[i] + 1}'),
                  ),
                ),
              if (_wrong != null) Text(_wrong!, style: TextStyle(color: cs.error)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _check,
                child: _saving ? const Text('Première sauvegarde…') : const Text('Vérifier et activer'),
              ),
              TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Revoir mes mots')),
            ],
            _ => [
              const SizedBox(height: 24),
              Icon(Icons.verified_user_rounded, size: 64, color: cs.secondary),
              const SizedBox(height: 16),
              Text('Sauvegarde activée', style: title, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'FouLove sauvegarde chaque jour, chiffré. Garde ton papier précieusement.',
                style: soft,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Terminé')),
            ],
          },
        ),
      ),
    );
  }
}

/// Revoir sa phrase (écran protégé).
class ShowPhraseScreen extends StatefulWidget {
  const ShowPhraseScreen({super.key, required this.phrase});

  final String phrase;

  @override
  State<ShowPhraseScreen> createState() => _ShowPhraseScreenState();
}

class _ShowPhraseScreenState extends State<ShowPhraseScreen> {
  @override
  void initState() {
    super.initState();
    _secure(true);
  }

  @override
  void dispose() {
    _secure(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ma phrase de récupération')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [_Words(words: widget.phrase.split(' '))],
      ),
    ),
  );
}

class _Words extends StatelessWidget {
  const _Words({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline),
      ),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 4.2,
        children: [
          for (final (i, w) in words.indexed)
            Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                Text(w, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ],
            ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.35))),
      ],
    ),
  );
}
