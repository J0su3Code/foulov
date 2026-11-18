import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/foulov_theme.dart';
import '../space/space_service.dart';

/// Apparence des bulles et du fond, choisie à deux (« Personnaliser ») et partagée chiffrée.
///
/// - Tes bulles : ta couleur, en dégradé, texte blanc.
/// - Ses bulles : neutres, légèrement teintées de sa couleur à lui (s'il en a choisi une).
/// - Forme : 0 carrées, 1 arrondies, 2 très douces.
class BubbleLook extends InheritedWidget {
  const BubbleLook({super.key, required this.shape, required this.mine, required this.theirs, required super.child});

  factory BubbleLook.from(SpaceService s, {Key? key, required Widget child}) => BubbleLook(
    key: key,
    shape: s.bubbleShape,
    mine: BubbleColors.of(s.myColor),
    theirs: s.partnerColor == null ? null : BubbleColors.of(s.partnerColor).$1,
    child: child,
  );

  final int shape;
  final (Color, Color) mine;
  final Color? theirs;

  static BubbleLook of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BubbleLook>() ??
      const BubbleLook(shape: 2, mine: (Color(0xFFE8417A), Color(0xFFC2185B)), theirs: null, child: SizedBox());

  Radius get radius => Radius.circular(switch (shape) {
    0 => 8,
    1 => 16,
    _ => 22,
  });

  Radius get tail => Radius.circular(shape == 0 ? 3 : 6);

  Color fg(BuildContext context, bool fromMe) => fromMe ? Colors.white : context.love.onTheirBubble;

  BoxDecoration box(BuildContext context, {required bool fromMe, required BorderRadius radius}) {
    if (fromMe) {
      return BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [mine.$1, mine.$2]),
      );
    }
    final base = context.love.theirBubble;
    return BoxDecoration(
      borderRadius: radius,
      color: theirs == null ? base : Color.lerp(base, theirs, context.night ? .22 : .12),
      border: Border.all(color: context.cs.outline.withValues(alpha: context.night ? .6 : 1)),
      boxShadow: context.night
          ? null
          : [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 3, offset: const Offset(0, 1))],
    );
  }

  @override
  bool updateShouldNotify(BubbleLook old) => old.shape != shape || old.mine != mine || old.theirs != theirs;
}

/// Fond de la conversation : un dégradé choisi, ou votre photo floutée et voilée (le texte reste lisible).
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.space, required this.child});

  final SpaceService space;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final night = context.night;
    final photo = space.wallpaper == 'photo' ? space.wallpaperPhoto : null;
    final colors = Wallpapers.colors(int.tryParse(space.wallpaper) ?? 0, night);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: colors),
          ),
        ),
        if (photo != null)
          FutureBuilder(
            future: space.open(photo.mediaId),
            builder: (context, snap) {
              final bytes = snap.data ?? (photo.media.thumb.isEmpty ? null : photo.media.thumb);
              if (bytes == null) return const SizedBox.shrink();
              return Stack(
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: TileMode.decal),
                    child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                  ColoredBox(color: context.cs.surface.withValues(alpha: night ? .55 : .45)),
                ],
              );
            },
          ),
        child,
      ],
    );
  }
}
