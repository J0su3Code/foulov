import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foulov/features/intro/intro_screen.dart';
import 'package:foulov/theme/foulov_theme.dart';

void main() {
  testWidgets("Avec animations réduites, l'accueil s'affiche directement", (tester) async {
    var started = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: FouLovTheme.jour,
          home: IntroScreen(onStart: () => started++, onJoin: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Commencer'), findsOneWidget);
    expect(find.text("J'ai un code d'invitation"), findsOneWidget);
    await tester.tap(find.text('Commencer'));
    expect(started, 1);
  });

  test('Les couleurs du splash correspondent au début de la vidéo', () {
    expect(FouLovColors.splashDay, const Color(0xFF0C2219));
    expect(FouLovColors.splashNight, const Color(0xFF0A0710));
  });
}
