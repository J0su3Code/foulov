import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/foulov_theme.dart';
import '../chat/bubble_look.dart';
import 'crop.dart';
import 'space_service.dart';
import 'widgets.dart';

/// Personnaliser la conversation : thèmes complets, fond (dégradés animés ou votre photo), motif, bulles, texte.
/// Disposition de WhatsApp (« Thème de la discussion ») : aperçu, thèmes, puis « Bulle de discussion » et
/// « Fond d'écran », chacun avec son aperçu en direct. Fond, motif, style et forme sont communs au couple ;
/// ta couleur et la taille du texte sont à toi.
class PersonalizeScreen extends StatefulWidget {
  const PersonalizeScreen({super.key, required this.space});

  final SpaceService space;

  @override
  State<PersonalizeScreen> createState() => _PersonalizeScreenState();
}

class _PersonalizeScreenState extends State<PersonalizeScreen> {
  SpaceService get space => widget.space;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final h = MediaQuery.sizeOf(context).height;
    return ListenableBuilder(
      listenable: space,
      builder: (context, _) {
        final wall = space.wallpaper;
        final wallIndex = int.tryParse(wall);
        return Scaffold(
          appBar: AppBar(title: const Text('Thème de la discussion')),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 28 + MediaQuery.paddingOf(context).bottom),
            children: [
              _Preview(space: space, height: (h * .30).clamp(210.0, 290.0)),
              const SectionLabel('Thèmes'),
              // Comme WhatsApp : deux rangées de petits téléphones, qu'on fait défiler de côté.
              SizedBox(
                height: 2 * 168 + 10,
                child: GridView.count(
                  scrollDirection: Axis.horizontal,
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 168 / 104,
                  children: [
                    for (var i = 0; i < ChatTheme.all.length; i++)
                      _ThemeCard(
                        theme: ChatTheme.all[i],
                        selected: space.theme == i,
                        onTap: () => _guard(context, () => space.applyTheme(i, ChatTheme.all[i])),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(
                  'Le fond d\'écran et les bulles seront modifiés, chez vous deux.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
              const SectionLabel('Personnaliser'),
              LoveCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _Row(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Bulle de discussion',
                      trailing: _Dot(gradient: [BubbleColors.of(space.myColor).$1, BubbleColors.of(space.myColor).$2]),
                      onTap: () => _open(context, _BubblePage(space: space)),
                    ),
                    Divider(height: 1, indent: 56, color: cs.outline),
                    _Row(
                      icon: Icons.wallpaper_rounded,
                      label: 'Fond d\'écran',
                      trailing: _Dot(
                        gradient: wallIndex == null
                            ? null
                            : Wallpapers.colors(wallIndex, context.night).take(2).toList(),
                        icon: wallIndex == null ? Icons.photo_outlined : null,
                      ),
                      onTap: () => _open(context, _WallpaperPage(space: space)),
                    ),
                    Divider(height: 1, indent: 56, color: cs.outline),
                    _Row(
                      icon: Icons.format_size_rounded,
                      label: 'Taille du texte',
                      trailing: Text(
                        const ['Petit', 'Normal', 'Grand'][space.textSize],
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      onTap: () => _textSize(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline_rounded, color: cs.onSurfaceVariant, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fond, motif et style des bulles voyagent chiffrés entre vos deux téléphones. Ta couleur, la '
                      'taille du texte et le mode jour ou nuit restent propres à chacun.',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.35),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _textSize(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: space,
      builder: (context, _) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, label) in const [(0, 'Petit'), (1, 'Normal'), (2, 'Grand')])
              ListTile(
                title: Text(label, style: TextStyle(fontSize: const [14.0, 16.0, 18.5][i])),
                trailing: space.textSize == i ? Icon(Icons.check_rounded, color: context.cs.primary) : null,
                onTap: () => _guard(context, () => space.set('text_size', '$i', personal: true)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// Applique un réglage ; s'il échoue (base locale), on le dit.
Future<void> _guard(BuildContext context, Future<void> Function() f) async {
  HapticFeedback.selectionClick();
  final messenger = ScaffoldMessenger.of(context);
  try {
    await f();
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Ce changement n\'a pas pu être enregistré.')));
  }
}

/// Ligne de la liste « Personnaliser » : icône, libellé, valeur, chevron.
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.trailing, required this.onTap});

  final IconData icon;
  final String label;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label, style: const TextStyle(fontSize: 16)),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        trailing,
        const SizedBox(width: 6),
        Icon(Icons.chevron_right_rounded, color: context.cs.onSurfaceVariant),
      ],
    ),
    onTap: onTap,
  );
}

/// Pastille de couleur (ou de fond) à droite d'une ligne.
class _Dot extends StatelessWidget {
  const _Dot({this.gradient, this.icon});

  final List<Color>? gradient;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.love.surface2,
      gradient: gradient == null ? null : LinearGradient(colors: gradient!),
      border: Border.all(color: context.cs.outline),
    ),
    child: icon == null ? null : Icon(icon, size: 14, color: context.cs.onSurfaceVariant),
  );
}

// ===================================================================== bulle de discussion

/// « Bulle de discussion » : l'aperçu en haut, puis style, forme et ta couleur. Chaque toucher s'y voit aussitôt.
class _BubblePage extends StatelessWidget {
  const _BubblePage({required this.space});

  final SpaceService space;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return ListenableBuilder(
      listenable: space,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Bulle de discussion')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: _Preview(space: space, height: (h * .34).clamp(220.0, 320.0)),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom),
                children: [
                  const SectionLabel('Ta couleur'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < BubbleColors.all.length; i++)
                        _Swatch(
                          color: BubbleColors.all[i],
                          selected: (space.myColor ?? 0) == i,
                          onTap: () => _guard(context, () => space.tweak('bubble_color', '$i', personal: true)),
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
                  const SectionLabel('Style'),
                  Row(
                    children: [
                      for (final (i, label) in const [(0, 'Dégradé'), (1, 'Uni'), (2, 'Verre'), (3, 'Contour')])
                        Expanded(
                          child: _StyleTile(
                            space: space,
                            style: i,
                            label: label,
                            selected: space.bubbleStyle == i,
                            onTap: () => _guard(context, () => space.tweak('bubble_style', '$i')),
                          ),
                        ),
                    ],
                  ),
                  const SectionLabel('Forme'),
                  Row(
                    children: [
                      for (final (i, label) in const [(0, 'Carrées'), (1, 'Arrondies'), (2, 'Très douces')])
                        Expanded(
                          child: _ShapeTile(
                            space: space,
                            shape: i,
                            label: label,
                            selected: space.bubbleShape == i,
                            onTap: () => _guard(context, () => space.tweak('bubble_shape', '$i')),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================================================================== fond d'écran

/// « Fond d'écran » : grande grille de fonds (comme « Couleur unie » de WhatsApp). Toucher un fond ouvre son aperçu
/// en plein écran, où l'on règle le motif (ou le flou de sa photo) avant de le définir.
class _WallpaperPage extends StatelessWidget {
  const _WallpaperPage({required this.space});

  final SpaceService space;

  @override
  Widget build(BuildContext context) {
    void preview(String wall) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _WallpaperPreview(space: space, wallpaper: wall),
      ),
    );

    Future<void> photo() async {
      if (space.wallpaperPhoto != null) return preview('photo');
      await _pickPhoto(context, space);
      if (context.mounted && space.wallpaperPhoto != null) preview('photo');
    }

    return ListenableBuilder(
      listenable: space,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Fond d\'écran')),
        body: GridView.count(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: .56,
          children: [
            _WallTile(
              selected: space.wallpaper == 'photo',
              label: 'Votre photo',
              onTap: photo,
              child: space.wallpaperPhoto == null
                  ? ColoredBox(
                      color: context.love.surface2,
                      child: Icon(Icons.add_photo_alternate_outlined, color: context.cs.primary, size: 30),
                    )
                  : PictureView(space: space, picture: space.wallpaperPhoto, fallback: const SizedBox()),
            ),
            for (var i = 0; i < Wallpapers.all.length; i++)
              _WallTile(
                selected: space.wallpaper == '$i',
                label: Wallpapers.all[i].$1,
                onTap: () => preview('$i'),
                child: FreeformGradient(colors: Wallpapers.colors(i, context.night)),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _pickPhoto(BuildContext context, SpaceService space) async {
  final f = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
  if (f == null || !context.mounted) return;
  final cropped = await cropFor(context, 'wallpaper', f.path);
  if (cropped == null || !context.mounted) return;
  await _guard(context, () => space.setPicture('wallpaper', cropped));
}

/// Aperçu plein écran d'un fond, avec une vraie petite conversation dessus. Rien n'est envoyé avant
/// « Définir le fond d'écran ».
class _WallpaperPreview extends StatefulWidget {
  const _WallpaperPreview({required this.space, required this.wallpaper});

  final SpaceService space;
  final String wallpaper;

  @override
  State<_WallpaperPreview> createState() => _WallpaperPreviewState();
}

class _WallpaperPreviewState extends State<_WallpaperPreview> {
  SpaceService get space => widget.space;
  bool get _photo => widget.wallpaper == 'photo';
  late int _pattern = space.pattern, _opacity = space.patternOpacity;
  late int _blur = space.photoBlur, _dim = space.photoDim;
  bool _saving = false;

  Future<void> _apply() async {
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    await _guard(context, () async {
      // Une valeur à la fois, seulement ce qui change : chaque changement est un petit message chiffré.
      if (space.wallpaper != widget.wallpaper) await space.tweak('wallpaper', widget.wallpaper);
      if (_photo) {
        if (_blur != space.photoBlur) await space.tweak('photo_blur', '$_blur');
        if (_dim != space.photoDim) await space.tweak('photo_dim', '$_dim');
      } else {
        if (_pattern != space.pattern) await space.tweak('pattern', '$_pattern');
        if (_opacity != space.patternOpacity) await space.tweak('pattern_opacity', '$_opacity');
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListenableBuilder(
      listenable: space,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_photo ? 'Votre photo' : Wallpapers.all[int.parse(widget.wallpaper)].$1),
          actions: [
            if (_photo)
              IconButton(
                tooltip: 'Choisir une autre photo',
                icon: const Icon(Icons.photo_library_outlined),
                onPressed: () => _pickPhoto(context, space),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: LayoutBuilder(
                  builder: (context, box) => _Preview(
                    space: space,
                    height: box.maxHeight,
                    background: (child) => ChatWallpaper(
                      space: space,
                      wallpaper: widget.wallpaper,
                      pattern: _pattern,
                      patternOpacity: _opacity,
                      photoBlur: _blur,
                      photoDim: _dim,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _photo
                  ? Column(
                      children: [
                        _Slider(
                          icon: Icons.blur_on_rounded,
                          label: 'Flou',
                          value: _blur.toDouble(),
                          max: 40,
                          onChanged: (v) => setState(() => _blur = v.round()),
                        ),
                        _Slider(
                          icon: Icons.brightness_4_outlined,
                          label: 'Assombrir',
                          value: _dim.toDouble(),
                          max: 80,
                          onChanged: (v) => setState(() => _dim = v.round()),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: 88,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: Patterns.all.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (context, i) => _PatternTile(
                              kind: i,
                              label: Patterns.all[i],
                              selected: _pattern == i,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _pattern = i);
                              },
                            ),
                          ),
                        ),
                        if (_pattern > 0)
                          _Slider(
                            icon: Icons.texture_rounded,
                            label: 'Intensité',
                            value: _opacity.toDouble(),
                            min: 3,
                            max: 30,
                            onChanged: (v) => setState(() => _opacity = v.round()),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: _saving || (_photo && space.wallpaperPhoto == null) ? null : _apply,
                  child: _saving
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                        )
                      : const Text('Définir le fond d\'écran'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aperçu en direct, comme un vrai téléphone : en-tête, messages (réponse, vocal, heure et coches), saisie.
/// Toucher fait glisser le dégradé.
class _Preview extends StatelessWidget {
  const _Preview({required this.space, required this.height, this.background});

  final SpaceService space;
  final double height;

  /// Fond à montrer à la place de celui du couple (aperçu avant de le définir).
  final Widget Function(Widget child)? background;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return BubbleLook.from(
      space,
      child: Builder(
        builder: (context) {
          final look = BubbleLook.of(context);
          BorderRadius shape(bool mine, {bool top = true}) => BorderRadius.only(
            topLeft: !mine && !top ? look.tail : look.radius,
            topRight: mine && !top ? look.tail : look.radius,
            bottomLeft: mine ? look.radius : look.tail,
            bottomRight: mine ? look.tail : look.radius,
          );
          Widget meta(bool mine, String time) {
            final fg = look.fg(context, mine);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time, style: TextStyle(fontSize: 10, color: fg.withValues(alpha: .62))),
                if (mine) ...[const SizedBox(width: 3), Icon(Icons.done_all_rounded, size: 13, color: fg)],
              ],
            );
          }

          Widget bubble(String text, bool mine, String time, {bool top = true, Widget? quote}) {
            final fg = look.fg(context, mine);
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                constraints: const BoxConstraints(maxWidth: 240),
                margin: EdgeInsets.only(top: top ? 6 : 2),
                padding: EdgeInsets.fromLTRB(quote == null ? 11 : 4, quote == null ? 7 : 4, 10, 6),
                decoration: look.box(
                  context,
                  fromMe: mine,
                  radius: shape(mine, top: top),
                ),
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ?quote,
                      Padding(
                        padding: EdgeInsets.only(left: quote == null ? 0 : 7, top: quote == null ? 0 : 4),
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          spacing: 6,
                          children: [
                            Text(
                              text,
                              style: TextStyle(color: fg, fontSize: look.fontSize * .85, height: 1.3),
                            ),
                            meta(mine, time),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // Réponse dans une de tes bulles : filet et nom de la personne citée.
          final onColored = look.style <= 1;
          final accent = onColored ? Colors.white : (look.theirs ?? cs.secondary);
          final myFg = look.fg(context, true);
          final quote = ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              color: onColored ? Colors.black.withValues(alpha: .13) : myFg.withValues(alpha: .07),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 3.5, color: accent),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(7, 4, 7, 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              space.chat.partnerLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: accent),
                            ),
                            Text(
                              'Tu as vu notre nouveau fond ?',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: myFg.withValues(alpha: .8)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          final theirFg = look.fg(context, false);
          final voice = Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 200,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.fromLTRB(4, 5, 10, 5),
              decoration: look.box(context, fromMe: false, radius: shape(false)),
              child: Row(
                children: [
                  Icon(Icons.play_arrow_rounded, color: theirFg, size: 26),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SizedBox(
                      height: 20,
                      child: Row(
                        children: [
                          for (final v in const <double>[.3, .6, .9, .5, .7, 1, .4, .8, .5, .3, .6, .9, .4, .7, .3, .5])
                            Expanded(
                              child: Container(
                                height: 3 + 15 * v,
                                margin: const EdgeInsets.symmetric(horizontal: .8),
                                decoration: BoxDecoration(
                                  color: theirFg.withValues(alpha: .35),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('0:07', style: TextStyle(fontSize: 10, color: theirFg.withValues(alpha: .7))),
                ],
              ),
            ),
          );

          return GestureDetector(
            onTap: ChatWallpaper.bump,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outline),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(23),
                child: Column(
                  children: [
                    // En-tête, comme dans la conversation.
                    Container(
                      color: cs.surface,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Row(
                        children: [
                          CoupleAvatar(space: space, size: 28),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  space.chat.partnerLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                                ),
                                Text('en ligne', style: TextStyle(fontSize: 11, color: context.love.ok)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: (background ?? (c) => ChatWallpaper(space: space, child: c))(
                        // Comme une vraie conversation : les derniers messages en bas, les plus anciens coupés en haut.
                        ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.bottomCenter,
                            maxHeight: double.infinity,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  bubble('Tu as vu notre nouveau fond ? 😍', false, '21:02'),
                                  bubble('Oui, il nous ressemble tellement 🥰', true, '21:03', quote: quote),
                                  bubble('Je t\'aime', true, '21:03', top: false),
                                  voice,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Saisie.
                    Container(
                      color: cs.surface,
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 30,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainer,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: cs.outline),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.emoji_emotions_outlined, size: 16, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Text('Message', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                            child: Icon(Icons.mic_rounded, size: 16, color: cs.onPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Un style de bulles, montré par une petite bulle dessinée dans ce style.
class _StyleTile extends StatelessWidget {
  const _StyleTile({
    required this.space,
    required this.style,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final SpaceService space;
  final int style;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final look = BubbleLook(
      shape: space.bubbleShape,
      mine: BubbleColors.of(space.myColor),
      theirs: null,
      style: style,
      child: const SizedBox(),
    );
    return _Choice(
      label: label,
      selected: selected,
      onTap: onTap,
      child: Container(
        width: 52,
        height: 26,
        alignment: Alignment.center,
        decoration: look.box(context, fromMe: true, radius: BorderRadius.all(look.radius)),
        child: Text('Coucou', style: TextStyle(fontSize: 10, color: look.fg(context, true))),
      ),
    );
  }
}

/// Une forme de bulles, montrée par deux petites bulles.
class _ShapeTile extends StatelessWidget {
  const _ShapeTile({
    required this.space,
    required this.shape,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final SpaceService space;
  final int shape;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final look = BubbleLook(
      shape: shape,
      mine: BubbleColors.of(space.myColor),
      theirs: null,
      style: space.bubbleStyle,
      child: const SizedBox(),
    );
    Widget b(bool mine, double w) => Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: w,
        height: 16,
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        decoration: look.box(
          context,
          fromMe: mine,
          radius: BorderRadius.only(
            topLeft: look.radius * .6,
            topRight: look.radius * .6,
            bottomLeft: mine ? look.radius * .6 : look.tail,
            bottomRight: mine ? look.tail : look.radius * .6,
          ),
        ),
      ),
    );
    return _Choice(
      label: label,
      selected: selected,
      onTap: onTap,
      child: SizedBox(width: 70, child: Column(children: [b(false, 46), b(true, 52)])),
    );
  }
}

/// Case de choix : un petit dessin, un libellé, un cadre quand elle est choisie.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap, required this.child});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: context.love.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? context.cs.primary : context.cs.outline, width: selected ? 2.4 : 1),
        ),
        child: Column(
          children: [
            SizedBox(height: 38, child: Center(child: child)),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
            ),
          ],
        ),
      ),
    ),
  );
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
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
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
                    // Coche du thème choisi, comme WhatsApp.
                    if (selected)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 12,
                        child: Center(
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: context.cs.primary,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: double.infinity,
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
    this.min = 0,
  });

  final IconData icon;
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(icon, size: 20, color: context.cs.onSurfaceVariant),
        const SizedBox(width: 8),
        SizedBox(width: 78, child: Text(label, style: const TextStyle(fontSize: 13.5))),
        Expanded(
          child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
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
