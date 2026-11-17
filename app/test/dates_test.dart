import 'package:flutter_test/flutter_test.dart';
import 'package:foulov/features/dates/reminders.dart';
import 'package:foulov/src/rust/api/chat.dart';

DateEntry _d(String title, String date, {bool yearly = true}) =>
    DateEntry(id: '0' * 32, title: title, date: date, yearly: yearly, remindDays: 1, updatedAt: 0);

void main() {
  final today = DateTime(2026, 11, 17, 15, 30);

  test('date annuelle : cette année si elle n\'est pas passée, sinon l\'an prochain', () {
    expect(nextOccurrence(DateTime(1998, 12, 1), yearly: true, today: today), DateTime(2026, 12, 1));
    expect(nextOccurrence(DateTime(1998, 4, 12), yearly: true, today: today), DateTime(2027, 4, 12));
    expect(nextOccurrence(DateTime(1998, 11, 17), yearly: true, today: today), DateTime(2026, 11, 17), reason: 'aujourd\'hui');
  });

  test('un 29 février tombe le 28 les années non bissextiles', () {
    expect(nextOccurrence(DateTime(2000, 2, 29), yearly: true, today: today), DateTime(2027, 2, 28));
    expect(nextOccurrence(DateTime(2000, 2, 29), yearly: true, today: DateTime(2027, 3, 1)), DateTime(2028, 2, 29));
  });

  test('date unique passée : plus affichée', () {
    expect(nextOccurrence(DateTime(2026, 1, 1), yearly: false, today: today), isNull);
    expect(nextOccurrence(DateTime(2027, 6, 1), yearly: false, today: today), DateTime(2027, 6, 1));
  });

  test('liste triée, années fêtées et anniversaire du couple', () {
    final l = upcoming([_d('Anniversaire d\'Inès', '1998-04-12'), _d('Concert', '2026-12-05', yearly: false)], '2022-03-12', today);
    expect(l.map((u) => u.title).toList(), ['Concert', 'Vos 5 ans ensemble', 'Anniversaire d\'Inès']);
    expect(l.last.years, 29);
    expect(l.first.daysLeft(today), 18);
    expect(l[1].coupleAnniversary, isTrue);
  });
}
