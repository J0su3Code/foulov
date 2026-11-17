import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata; // 10 ans de règles, tous les fuseaux et alias : léger
import 'package:timezone/timezone.dart' as tz;

import '../../src/rust/api/chat.dart';

/// Une date à venir, telle qu'affichée et rappelée.
class Upcoming {
  const Upcoming({required this.title, required this.next, this.entry, this.years, this.coupleAnniversary = false});

  final String title;

  /// Prochaine occurrence (minuit, heure locale).
  final DateTime next;

  /// `null` pour l'anniversaire du couple, calculé depuis « ensemble depuis ».
  final DateEntry? entry;

  /// Nombre d'années fêtées à cette occurrence (dates annuelles dont l'année est passée).
  final int? years;
  final bool coupleAnniversary;

  int daysLeft(DateTime today) => DateTime(next.year, next.month, next.day).difference(_day(today)).inDays;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

bool _leap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

/// Prochaine occurrence d'une date (un 29 février tombe le 28 les années non bissextiles).
DateTime? nextOccurrence(DateTime d, {required bool yearly, required DateTime today}) {
  final t = _day(today);
  if (!yearly) return _day(d).isBefore(t) ? null : _day(d);
  DateTime at(int y) => DateTime(y, d.month, d.month == 2 && d.day == 29 && !_leap(y) ? 28 : d.day);
  final thisYear = at(t.year);
  return thisYear.isBefore(t) ? at(t.year + 1) : thisYear;
}

/// Toutes les dates à venir (y compris l'anniversaire du couple), de la plus proche à la plus lointaine.
List<Upcoming> upcoming(List<DateEntry> dates, String? togetherSince, DateTime today) {
  final out = <Upcoming>[];
  final since = togetherSince == null ? null : DateTime.tryParse(togetherSince);
  if (since != null) {
    final n = nextOccurrence(since, yearly: true, today: today)!;
    final y = n.year - since.year;
    out.add(
      Upcoming(
        title: y <= 0 ? 'Le début de votre histoire' : (y == 1 ? 'Votre premier anniversaire' : 'Vos $y ans ensemble'),
        next: n,
        years: y > 0 ? y : null,
        coupleAnniversary: true,
      ),
    );
  }
  for (final e in dates) {
    final d = DateTime.tryParse(e.date);
    if (d == null) continue;
    final n = nextOccurrence(d, yearly: e.yearly, today: today);
    if (n == null) continue;
    final y = e.yearly && d.year < n.year ? n.year - d.year : null;
    out.add(Upcoming(title: e.title, next: n, entry: e, years: y));
  }
  out.sort((a, b) => a.next.compareTo(b.next));
  return out;
}

/// Rappels programmés **sur le téléphone** (le serveur ne sait ni quand ni quoi). Texte affiché à 9 h, heure locale.
abstract final class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _first = 1000, _last = 1499;

  static Future<void>? _init;

  /// Préparé au premier besoin, jamais au démarrage : un rappel ne doit pas retarder l'ouverture de l'app.
  static Future<void> init() => _init ??= _doInit();

  static Future<void> _doInit() async {
    try {
      if (kDebugMode) debugPrint('[FOULOVE] rappels : préparation');
      tzdata.initializeTimeZones();
      final name = (await FlutterTimezone.getLocalTimezone()).identifier;
      try {
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        // Fuseau inconnu de la base : on garde UTC plutôt que de renoncer aux rappels.
        tz.setLocalLocation(tz.UTC);
      }
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
      );
      _ready = true;
      if (kDebugMode) debugPrint('[FOULOVE] rappels : prêts');
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] rappels : $e');
    }
  }

  static String _when(int days) => switch (days) {
    0 => 'Aujourd\'hui',
    1 => 'Demain',
    7 => 'Dans une semaine',
    _ => 'Dans $days jours',
  };

  /// Reprogramme tous les rappels (après chaque changement de date ou de « ensemble depuis »).
  static Future<void> reschedule(List<DateEntry> dates, String? togetherSince) async {
    await init();
    if (!_ready) return;
    try {
      for (final p in await _plugin.pendingNotificationRequests()) {
        if (p.id >= _first && p.id <= _last) await _plugin.cancel(id: p.id);
      }
      final now = tz.TZDateTime.now(tz.local);
      var id = _first;
      for (final u in upcoming(dates, togetherSince, now)) {
        // Anniversaire du couple : rappel le jour même ; sinon selon le choix de la date.
        final before = u.coupleAnniversary ? 0 : u.entry?.remindDays;
        if (before == null || id > _last) continue;
        final at = tz.TZDateTime(tz.local, u.next.year, u.next.month, u.next.day, 9).subtract(Duration(days: before));
        if (at.isBefore(now)) continue;
        await _plugin.zonedSchedule(
          id: id++,
          scheduledDate: at,
          title: 'FouLove',
          body: '${_when(before)} : ${u.title}',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'dates',
              'Dates importantes',
              channelDescription: 'Rappels de vos dates, programmés sur ce téléphone',
              importance: Importance.high,
              priority: Priority.high,
              // Écran verrouillé : le texte reste masqué si le téléphone masque les contenus sensibles.
              visibility: NotificationVisibility.private,
              icon: 'ic_notification',
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] rappels : $e');
    }
  }
}
