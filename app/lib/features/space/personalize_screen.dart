import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/foulov_theme.dart';
import '../chat/bubble_look.dart';
import 'space_service.dart';
import 'crop.dart';
import 'widgets.dart';

/// Personnaliser la conversation : forme des bulles, ta couleur, le fond. Aperçu en direct.
/// La forme et le fond sont communs au couple ; ta couleur est la tienne (elle teinte tes bulles chez l'autre aussi).
class PersonalizeScreen extends StatelessWidget {
  const PersonalizeScreen({super.key, required this.space});

  final SpaceService space;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: space,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Personnaliser')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _Preview(space: space),
            const SectionLabel('Forme des bulles'),
            Wrap(
              spacing: 8,
              children: [
                for (final (i, label) in const [(0, 'Carrées'), (1, 'Arrondies'), (2, 'Très douces')])
                  ChoiceChip(
                    label: Text(label),
                    selected: space.bubbleShape == i,
                    showCheckmark: false,
                    onSelected: (_) => space.set('bubble_shape', '$i'),
                  ),
              ],
            ),
            const SectionLabel('Ta couleur'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < BubbleColors.all.length; i++)
                  _Swatch(
                    colors: BubbleColors.all[i],
                    selected: (space.myColor ?? 0) == i,
                    onTap: () => space.set('bubble_color', '$i', personal: true),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(
                space.partnerColor == null
                    ? 'Tes bulles prennent ta couleur. ${space.chat.partnerLabel} choisit la sienne de son côté.'
                    : 'Tes bulles prennent ta couleur ; les siennes, celle choisie par ${space.chat.partnerLabel}.',
                style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 13),
              ),
            ),
            const SectionLabel('Fond de la conversation'),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 3 / 4,
              children: [
                for (var i = 0; i < Wallpapers.all.length; i++)
                  _WallTile(
                    selected: space.wallpaper == '$i',
                    label: Wallpapers.all[i].$1,
                    onTap: () => space.set('wallpaper', '$i'),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: Wallpapers.colors(i, context.night),
                        ),
                      ),
                    ),
                  ),
                _WallTile(
                  selected: space.wallpaper == 'photo',
                  label: 'Votre photo',
                  light: true,
                  onTap: () => _photo(context),
                  child: space.wallpaperPhoto == null
                      ? ColoredBox(
                          color: context.love.surface2,
                          child: Icon(Icons.add_photo_alternate_outlined, color: context.cs.primary),
                        )
                      : PictureView(space: space, picture: space.wallpaperPhoto, fallback: const SizedBox()),
                ),
              ],
            ),
            const SizedBox(height: 18),
            LoveCard(
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: context.cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ces choix voyagent chiffrés entre vos deux téléphones. Le mode jour ou nuit reste propre à chacun.',
                      style: TextStyle(fontSize: 13, color: context.cs.onSurfaceVariant, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _photo(BuildContext context) async {
    if (space.wallpaperPhoto != null && space.wallpaper != 'photo') {
      await space.set('wallpaper', 'photo');
      return;
    }
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    if (f == null || !context.mounted) return;
    final cropped = await cropFor(context, 'wallpaper', f.path);
    if (cropped == null) return;
    try {
      await space.setPicture('wallpaper', cropped);
      await space.set('wallpaper', 'photo');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cette photo n\'a pas pu être utilisée.')));
      }
    }
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.space});

  final SpaceService space;

  @override
  Widget build(BuildContext context) {
    return BubbleLook.from(
      space,
      child: Builder(
        builder: (context) {
          final look = BubbleLook.of(context);
          Widget bubble(String text, bool mine) => Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: look.box(
                context,
                fromMe: mine,
                radius: BorderRadius.only(
                  topLeft: look.radius,
                  topRight: look.radius,
                  bottomLeft: mine ? look.radius : look.tail,
                  bottomRight: mine ? look.tail : look.radius,
                ),
              ),
              child: Text(text, style: TextStyle(color: look.fg(context, mine), fontSize: 15)),
            ),
          );
          return ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 170,
              child: ChatWallpaper(
                space: space,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      bubble('Tu as choisi notre fond ? 😍', false),
                      bubble('Oui, il nous ressemble 🥰', true),
                      bubble('Parfait ❤️', false),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colors, required this.selected, required this.onTap});

  final (Color, Color) colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 40,
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? context.cs.primary : Colors.transparent, width: 2.4),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [colors.$1, colors.$2]),
        ),
        child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
      ),
    ),
  );
}

class _WallTile extends StatelessWidget {
  const _WallTile({
    required this.selected,
    required this.label,
    required this.onTap,
    required this.child,
    this.light = false,
  });

  final bool selected, light;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? context.cs.primary : context.cs.outline, width: selected ? 2.4 : 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned(
              left: 0,
              right: 0,
              bottom: 5,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: light ? context.cs.onSurface : context.cs.onSurface.withValues(alpha: .75),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
