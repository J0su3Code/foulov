import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/foulov_theme.dart';
import '../chat/bubble_look.dart';
import 'crop.dart';
import 'space_service.dart';
import 'widgets.dart';

/// Personnaliser la conversation : thèmes complets, fond (dégradés animés ou votre photo), motif, bulles, texte.
/// Aperçu en direct. Fond, motif, style et forme sont communs au couple ; ta couleur et la taille du texte sont à toi.
class PersonalizeScreen extends StatefulWidget {
  const PersonalizeScreen({super.key, required this.space});

  final SpaceService space;

  @override
  State<PersonalizeScreen> createState() => _PersonalizeScreenState();
}

class _PersonalizeScreenState extends State<PersonalizeScreen> {
  SpaceService get space => widget.space;

  // Curseurs : valeur affichée pendant le glissement, envoyée au relâchement (un seul message chiffré).
  double? _opacity, _blur, _dim;

  Future<void> _guard(Future<void> Function() f) async {
    HapticFeedback.selectionClick();
    try {
      await f();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ce changement n\'a pas pu être enregistré.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: space,
      builder: (context, _) {
        final photo = space.wallpaper == 'photo';
        return Scaffold(
          appBar: AppBar(title: const Text('Personnaliser')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              _Preview(space: space),
              const SectionLabel('Thèmes'),
              SizedBox(
                height: 132,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ChatTheme.all.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _ThemeCard(
                    theme: ChatTheme.all[i],
                    selected: space.theme == i,
                    onTap: () => _guard(() => space.applyTheme(i, ChatTheme.all[i])),
                  ),
                ),
              ),
              const SectionLabel('Fond'),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 3 / 4.4,
                children: [
                  _WallTile(
                    selected: photo,
                    label: 'Votre photo',
                    onTap: () => _photo(context),
                    child: space.wallpaperPhoto == null
                        ? ColoredBox(
                            color: context.love.surface2,
                            child: Icon(Icons.add_photo_alternate_outlined, color: context.cs.primary),
                          )
                        : PictureView(space: space, picture: space.wallpaperPhoto, fallback: const SizedBox()),
                  ),
                  for (var i = 0; i < Wallpapers.all.length; i++)
                    _WallTile(
                      selected: space.wallpaper == '$i',
                      label: Wallpapers.all[i].$1,
                      onTap: () => _guard(() => space.tweak('wallpaper', '$i')),
                      child: FreeformGradient(colors: Wallpapers.colors(i, context.night)),
                    ),
                ],
              ),
              if (photo) ...[
                _Slider(
                  icon: Icons.blur_on_rounded,
                  label: 'Flou',
                  value: _blur ?? space.photoBlur.toDouble(),
                  max: 40,
                  onChanged: (v) => setState(() => _blur = v),
                  onEnd: (v) => _guard(() async {
                    await space.tweak('photo_blur', '${v.round()}');
                    setState(() => _blur = null);
                  }),
                ),
                _Slider(
                  icon: Icons.brightness_4_outlined,
                  label: 'Assombrir',
                  value: _dim ?? space.photoDim.toDouble(),
                  max: 80,
                  onChanged: (v) => setState(() => _dim = v),
                  onEnd: (v) => _guard(() async {
                    await space.tweak('photo_dim', '${v.round()}');
                    setState(() => _dim = null);
                  }),
                ),
              ] else ...[
                const SectionLabel('Motif'),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: Patterns.all.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => _PatternTile(
                      kind: i,
                      label: Patterns.all[i],
                      selected: space.pattern == i,
                      onTap: () => _guard(() => space.tweak('pattern', '$i')),
                    ),
                  ),
                ),
                if (space.pattern > 0)
                  _Slider(
                    icon: Icons.texture_rounded,
                    label: 'Intensité',
                    value: _opacity ?? space.patternOpacity.toDouble(),
                    min: 3,
                    max: 30,
                    onChanged: (v) => setState(() => _opacity = v),
                    onEnd: (v) => _guard(() async {
                      await space.tweak('pattern_opacity', '${v.round()}');
                      setState(() => _opacity = null);
                    }),
                  ),
              ],
              const SectionLabel('Bulles'),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('Dégradé')),
                  ButtonSegment(value: 1, label: Text('Uni')),
                  ButtonSegment(value: 2, label: Text('Verre')),
                  ButtonSegment(value: 3, label: Text('Contour')),
                ],
                selected: {space.bubbleStyle},
                onSelectionChanged: (s) => _guard(() => space.tweak('bubble_style', '${s.first}')),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final (i, label) in const [(0, 'Carrées'), (1, 'Arrondies'), (2, 'Très douces')])
                    ChoiceChip(
                      label: Text(label),
                      selected: space.bubbleShape == i,
                      showCheckmark: false,
                      onSelected: (_) => _guard(() => space.tweak('bubble_shape', '$i')),
                    ),
                ],
              ),
              const SectionLabel('Ta couleur'),
              Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < BubbleColors.all.length; i++)
                    _Swatch(
                      color: BubbleColors.all[i],
                      selected: (space.myColor ?? 0) == i,
                      onTap: () => _guard(() => space.tweak('bubble_color', '$i', personal: true)),
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
              const SectionLabel('Taille du texte'),
              Row(
                children: [
                  Text('A', style: TextStyle(fontSize: 13, color: context.cs.onSurfaceVariant)),
                  Expanded(
                    child: Slider(
                      value: space.textSize.toDouble(),
                      max: 2,
                      divisions: 2,
                      onChanged: (v) => _guard(() => space.set('text_size', '${v.round()}', personal: true)),
                    ),
                  ),
                  Text('A', style: TextStyle(fontSize: 20, color: context.cs.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 10),
              LoveCard(
                child: Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: context.cs.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ces choix voyagent chiffrés entre vos deux téléphones. La taille du texte et le mode jour ou '
                        'nuit restent propres à chacun.',
                        style: TextStyle(fontSize: 13, color: context.cs.onSurfaceVariant, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _photo(BuildContext context) async {
    if (space.wallpaperPhoto != null && space.wallpaper != 'photo') {
      await _guard(() => space.tweak('wallpaper', 'photo'));
      return;
    }
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    if (f == null || !context.mounted) return;
    final cropped = await cropFor(context, 'wallpaper', f.path);
    if (cropped == null) return;
    await _guard(() async {
      await space.setPicture('wallpaper', cropped);
      await space.tweak('wallpaper', 'photo');
    });
  }
}

/// Aperçu en direct : une petite conversation sur le fond choisi. Toucher fait glisser le dégradé.
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
              child: Text(
                text,
                style: TextStyle(color: look.fg(context, mine), fontSize: look.fontSize),
              ),
            ),
          );
          return GestureDetector(
            onTap: ChatWallpaper.bump,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 230,
                child: ChatWallpaper(
                  space: space,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        bubble('Tu as vu notre nouveau fond ? 😍', false),
                        bubble('Oui, il nous ressemble tellement 🥰', true),
                        bubble('Comme nous ❤️', false),
                        bubble('Je t\'aime', true),
                      ],
                    ),
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

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.theme, required this.selected, required this.onTap});

  final ChatTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final night = context.night;
    final look = BubbleLook(
      shape: theme.shape,
      mine: BubbleColors.of(theme.color),
      theirs: null,
      style: theme.style,
      textScale: .8,
      child: const SizedBox(),
    );
    Widget mini(bool mine, double w) => Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: w,
        height: 14,
        margin: const EdgeInsets.symmetric(vertical: 2.5),
        decoration: look.box(
          context,
          fromMe: mine,
          radius: BorderRadius.all(Radius.circular(theme.shape == 0 ? 4 : 8)),
        ),
      ),
    );
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 86,
            height: 104,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? context.cs.primary : Colors.transparent, width: 2.4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FreeformGradient(colors: Wallpapers.colors(theme.wallpaper, night)),
                  if (theme.pattern > 0)
                    CustomPaint(
                      painter: PatternPainter(
                        theme.pattern,
                        (night ? Colors.white : const Color(0xFF3A1A2A)).withValues(alpha: theme.opacity / 100 + .04),
                        scale: .5,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [mini(false, 44), mini(true, 52), mini(false, 32)],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 90,
            child: Text(
              theme.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatternTile extends StatelessWidget {
  const _PatternTile({required this.kind, required this.label, required this.selected, required this.onTap});

  final int kind;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: context.love.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? context.cs.primary : context.cs.outline, width: selected ? 2.4 : 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: kind == 0
                ? Icon(Icons.block_rounded, color: context.cs.onSurfaceVariant)
                : CustomPaint(painter: PatternPainter(kind, context.cs.onSurface.withValues(alpha: .55), scale: .55)),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 72,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.icon,
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    required this.onEnd,
    this.min = 0,
  });

  final IconData icon;
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged, onEnd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(icon, size: 20, color: context.cs.onSurfaceVariant),
        const SizedBox(width: 8),
        SizedBox(width: 78, child: Text(label, style: const TextStyle(fontSize: 13.5))),
        Expanded(
          child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged, onChangeEnd: onEnd),
        ),
      ],
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final (String, Color, Color) color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: color.$1,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 42,
        height: 42,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? context.cs.primary : Colors.transparent, width: 2.4),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.$2, color.$3],
            ),
          ),
          child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
        ),
      ),
    ),
  );
}

class _WallTile extends StatelessWidget {
  const _WallTile({required this.selected, required this.label, required this.onTap, required this.child});

  final bool selected;
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
                  color: context.cs.onSurface.withValues(alpha: .8),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
