import 'package:flutter_test/flutter_test.dart';
import 'package:foulov/features/lock/app_lock.dart';

void main() {
  test('délai du code FouLove : 30 s après 5 erreurs, puis double, plafonné à 1 h', () {
    expect(AppLock.delayFor(4), Duration.zero);
    expect(AppLock.delayFor(5), const Duration(seconds: 30));
    expect(AppLock.delayFor(6), const Duration(seconds: 60));
    expect(AppLock.delayFor(11), const Duration(minutes: 32));
    expect(AppLock.delayFor(12), const Duration(hours: 1));
  });

  test('le délai ne retombe jamais à zéro, même après des milliers d\'erreurs (débordement)', () {
    for (var n = 5; n < 5000; n++) {
      expect(AppLock.delayFor(n) >= const Duration(seconds: 30), isTrue, reason: '$n erreurs');
    }
    expect(AppLock.delayFor(64), const Duration(hours: 1));
    expect(AppLock.delayFor(1000000), const Duration(hours: 1));
  });
}
