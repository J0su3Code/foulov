import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../src/rust/api/chat.dart';
import '../chat/chat_service.dart';
import 'reminders.dart';

/// Onglet « Dates » : vos dates importantes, partagées chiffrées entre vos deux téléphones.
class DatesScreen extends StatelessWidget {
  const DatesScreen({super.key, required this.service});

  final ChatService service;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final t = Theme.of(context);
        final cs = t.colorScheme;
        final today = DateTime.now();
        final list = upcoming(service.dates, service.profile.togetherSince, today);
        return Scaffold(
          backgroundColor: cs.surface,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ajouter une date'),
          ),
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Dates', style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Partagées entre vos deux téléphones, chiffrées. Les rappels sont programmés sur ton téléphone.',
                    style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 18),
                if (list.isEmpty)
                  _EmptyDates(hasSince: service.profile.togetherSince != null)
                else ...[
                  _NextCard(u: list.first, today: today, onTap: () => _open(context, list.first)),
                  if (list.length > 1) ...[
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('Ensuite', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 8),
                    for (final u in list.skip(1)) _Row(u: u, today: today, onTap: () => _open(context, u)),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _open(BuildContext context, Upcoming u) {
    if (u.coupleAnniversary) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cette date vient de « Ensemble depuis », modifiable dans Notre espace.')),
      );
      return;
    }
    _edit(context, u.entry);
  }

  Future<void> _edit(BuildContext context, DateEntry? e) async {
    final r = await showModalBottomSheet<_Edit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DateSheet(entry: e),
    );
    if (r == null || !context.mounted) return;
    try {
      if (r.delete) {
        await service.deleteDate(e!.id);
      } else {
        await service.saveDate(r.entry!);
      }
      HapticFeedback.lightImpact();
    } catch (err) {
      if (kDebugMode) debugPrint('[FOULOVE] date : $err');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ce changement n\'a pas pu être enregistré.')));
      }
    }
  }
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
const _days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

String _pretty(DateTime d, {bool weekday = false}) =>
    '${weekday ? '${_days[d.weekday - 1]} ' : ''}${d.day} ${_months[d.month - 1]} ${d.year}';

String _left(int n) => switch (n) {
  0 => 'Aujourd\'hui',
  1 => 'Demain',
  _ => 'Dans $n jours',
};

class _NextCard extends StatelessWidget {
  const _NextCard({required this.u, required this.today, required this.onTap});

  final Upcoming u;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = u.daysLeft(today);
    return Material(
      color: cs.secondary.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: cs.secondary, borderRadius: BorderRadius.circular(18)),
                alignment: Alignment.center,
                child: n <= 1
                    ? Text(n == 0 ? '🎉' : '✨', style: const TextStyle(fontSize: 30))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$n',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSecondary),
                          ),
                          Text('jours', style: TextStyle(fontSize: 11, color: cs.onSecondary)),
                        ],
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _left(n),
                      style: TextStyle(fontWeight: FontWeight.w600, color: cs.secondary),
                    ),
                    const SizedBox(height: 2),
                    Text(u.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      _pretty(u.next, weekday: true) +
                          (u.years != null && !u.coupleAnniversary ? ' · ${u.years} ans' : ''),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.u, required this.today, required this.onTap});

  final Upcoming u;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = u.daysLeft(today);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: cs.surfaceContainer,
        child: Text(u.coupleAnniversary ? '💞' : (u.entry!.yearly ? '🎂' : '📌')),
      ),
      title: Text(u.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_pretty(u.next) + (u.years != null && !u.coupleAnniversary ? ' · ${u.years} ans' : '')),
      trailing: Text(_left(n), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
    );
  }
}

class _EmptyDates extends StatelessWidget {
  const _EmptyDates({required this.hasSince});

  final bool hasSince;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Icon(Icons.event_available_rounded, size: 52, color: t.colorScheme.secondary),
          const SizedBox(height: 12),
          Text('Vos dates à vous', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Anniversaires, première rencontre, prochain voyage… Ajoute vos dates : '
            '${hasSince ? '' : 'renseigne aussi « Ensemble depuis » dans Notre espace pour fêter votre anniversaire. '}'
            'Ton amour les verra aussi.',
            textAlign: TextAlign.center,
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Edit {
  const _Edit({this.entry, this.delete = false});
  final DateEntry? entry;
  final bool delete;
}

/// Ajout ou modification d'une date.
class _DateSheet extends StatefulWidget {
  const _DateSheet({required this.entry});

  final DateEntry? entry;

  @override
  State<_DateSheet> createState() => _DateSheetState();
}

class _DateSheetState extends State<_DateSheet> {
  late final _title = TextEditingController(text: widget.entry?.title ?? '');
  late DateTime? _date = widget.entry == null ? null : DateTime.tryParse(widget.entry!.date);
  late bool _yearly = widget.entry?.yearly ?? true;
  late int? _remind = widget.entry == null ? 1 : widget.entry!.remindDays;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = _title.text.trim().isNotEmpty && _date != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.entry == null ? 'Nouvelle date' : 'Modifier la date',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Quoi ?',
                hintText: 'Anniversaire d\'Inès, notre rencontre…',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded),
              label: Text(_date == null ? 'Choisir le jour' : _pretty(_date!)),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date ?? DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime(DateTime.now().year + 10),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Chaque année'),
              subtitle: const Text('Anniversaires, dates de couple…'),
              value: _yearly,
              onChanged: (v) => setState(() => _yearly = v),
            ),
            const SizedBox(height: 4),
            Text('Rappel', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (v, l) in [(null, 'Aucun'), (0, 'Le jour même'), (1, 'La veille'), (7, 'Une semaine avant')])
                  ChoiceChip(
                    label: Text(l),
                    selected: _remind == v,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _remind = v),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: ok
                  ? () {
                      final d = _date!;
                      final iso =
                          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                      Navigator.pop(
                        context,
                        _Edit(
                          entry: DateEntry(
                            id: widget.entry?.id ?? '',
                            title: _title.text.trim(),
                            date: iso,
                            yearly: _yearly,
                            remindDays: _remind,
                            updatedAt: 0,
                          ),
                        ),
                      );
                    }
                  : null,
              child: const Text('Enregistrer'),
            ),
            if (widget.entry != null)
              TextButton(
                onPressed: () => Navigator.pop(context, const _Edit(delete: true)),
                child: Text('Supprimer cette date', style: TextStyle(color: cs.error)),
              ),
          ],
        ),
      ),
    );
  }
}
