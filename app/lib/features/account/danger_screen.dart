import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../couple/couple_screens.dart';
import '../lock/app_lock.dart';
import 'account_service.dart';

/// Confirmer une action sans retour (fermer la bulle, supprimer le compte) : ce qui disparaît, le mot à taper,
/// puis le code FouLove (ou l'empreinte) si un verrou est actif.
class DangerScreen extends StatefulWidget {
  const DangerScreen({super.key, required this.deleteAccount, this.partnerName});

  /// Faux : fermer la bulle (le compte reste). Vrai : supprimer le compte.
  final bool deleteAccount;
  final String? partnerName;

  /// Ouvre l'écran ; tout se fait ici (confirmation, serveur, remise à zéro).
  static Future<void> open(BuildContext context, {required bool deleteAccount, String? partnerName}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => DangerScreen(deleteAccount: deleteAccount, partnerName: partnerName),
        ),
      );

  @override
  State<DangerScreen> createState() => _DangerScreenState();
}

class _DangerScreenState extends State<DangerScreen> {
  final _word = TextEditingController();
  bool _busy = false;
  String? _error;

  String get _expected => widget.deleteAccount ? 'SUPPRIMER' : 'FERMER';

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final reason = widget.deleteAccount ? 'Confirme la suppression de ton compte' : 'Confirme pour fermer votre bulle';
    if (!await AppLock.instance.confirm(reason, askPin: () => askCurrentPin(context))) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.heavyImpact();
    final nav = Navigator.of(context);
    final db = Supabase.instance.client;
    try {
      // La messagerie se démonte, tout s'efface, puis on revient à l'accueil (création d'une nouvelle bulle).
      await CoupleGate.end(
        () => widget.deleteAccount ? AccountService.deleteAccount(db) : AccountService.closeCouple(db),
      );
      nav.popUntil((r) => r.isFirst);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Ça n\'a pas abouti (réseau ?). Rien n\'a été effacé sur ce téléphone : réessaie.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final who = widget.partnerName ?? 'ton amour';
    final points = widget.deleteAccount
        ? [
            'Ton compte FouLove est supprimé, définitivement.',
            'Votre bulle est fermée, chez toi et chez $who.',
            'Vos messages, photos, vidéos, vocaux, lettres et souvenirs sont effacés de ce téléphone et de nos serveurs.',
            'Ta sauvegarde chiffrée est supprimée. Ta phrase de 24 mots ne servira plus à rien.',
          ]
        : [
            'Votre bulle est fermée, chez toi et chez $who : plus rien ne peut être envoyé.',
            'Vos photos, vidéos et vocaux chiffrés sont retirés de nos serveurs, ainsi que ta sauvegarde.',
            'Ce téléphone est remis à zéro. $who verra que la bulle est fermée et pourra effacer la sienne.',
            'Ton compte reste : tu pourras créer une nouvelle bulle.',
          ];
    return Scaffold(
      appBar: AppBar(title: Text(widget.deleteAccount ? 'Supprimer mon compte' : 'Fermer notre bulle')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Icon(
              widget.deleteAccount ? Icons.delete_forever_rounded : Icons.heart_broken_outlined,
              size: 52,
              color: cs.error,
            ),
            const SizedBox(height: 12),
            Text(
              'C\'est sans retour.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.remove_circle_outline_rounded, size: 18, color: cs.error),
                    const SizedBox(width: 10),
                    Expanded(child: Text(p, style: const TextStyle(height: 1.35))),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text('Pour confirmer, tape $_expected :', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextField(
              controller: _word,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: _expected),
            ),
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: cs.error))],
            const SizedBox(height: 20),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
                onPressed: _word.text.trim().toUpperCase() == _expected ? _go : null,
                child: Text(widget.deleteAccount ? 'Supprimer mon compte' : 'Fermer notre bulle'),
              ),
          ],
        ),
      ),
    );
  }
}
