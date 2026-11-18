import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../src/rust/api/space.dart';
import '../../theme/foulov_theme.dart';
import 'space_service.dart';

// ===================================================================== dates en français

const monthsLong = [
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
const monthsShort = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const weekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

/// « 12 mars 2023 » ; sans l'année si `year` est faux.
String frDate(DateTime d, {bool year = true, bool weekday = false}) =>
    '${weekday ? '${weekdays[d.weekday - 1]} ' : ''}${d.day} ${monthsLong[d.month - 1]}${year ? ' ${d.year}' : ''}';

/// Nombre avec une espace fine pour les milliers : « 48 213 ».
String frNumber(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// « il y a 2 h », « il y a 5 min », « à l'instant ».
String ago(int ms) {
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return 'à l\'instant';
  if (d.inHours < 1) return 'il y a ${d.inMinutes} min';
  if (d.inDays < 1) return 'il y a ${d.inHours} h';
  return 'il y a ${d.inDays} j';
}

DateTime? parseIso(String? s) => s == null ? null : DateTime.tryParse(s);

/// Anniversaire « MM-JJ » ou « AAAA-MM-JJ » → (mois, jour, année ?).
(int, int, int?)? parseBirthday(String? s) {
  if (s == null) return null;
  final p = s.split('-').map(int.tryParse).toList();
  if (p.any((x) => x == null)) return null;
  return p.length == 2 ? (p[0]!, p[1]!, null) : (p.length == 3 ? (p[1]!, p[2]!, p[0]) : null);
}

/// Prochaine occurrence d'un jour de l'année (aujourd'hui compris).
DateTime nextDay(int month, int day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var d = DateTime(now.year, month, day);
  if (d.isBefore(today)) d = DateTime(now.year + 1, month, day);
  return d;
}

int daysUntil(DateTime d) {
  final now = DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
}

// ===================================================================== images chiffrées

/// Image d'un fichier chiffré : la miniature tout de suite, puis l'image entière déchiffrée en mémoire.
class SecureImage extends StatefulWidget {
  const SecureImage({super.key, required this.space, required this.id, required this.thumb, this.fit = BoxFit.cover});

  final SpaceService space;
  final String id;
  final Uint8List thumb;
  final BoxFit fit;

  @override
  State<SecureImage> createState() => _SecureImageState();
}

class _SecureImageState extends State<SecureImage> {
  Uint8List? _full;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SecureImage old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      _full = null;
      _load();
    } else if (_full == null && old.thumb != widget.thumb) {
      _load(); // vient d'être téléchargée
    }
  }

  Future<void> _load() async {
    final id = widget.id;
    final b = await widget.space.open(id);
    if (mounted && id == widget.id && b != null) setState(() => _full = b);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _full ?? widget.thumb;
    if (bytes.isEmpty) return ColoredBox(color: context.love.surface2);
    return Image.memory(
      bytes,
      fit: widget.fit,
      gaplessPlayback: true,
      filterQuality: _full == null ? FilterQuality.low : FilterQuality.medium,
    );
  }
}

/// Photo d'un emplacement du couple, ou `fallback` s'il n'y en a pas.
class PictureView extends StatelessWidget {
  const PictureView({super.key, required this.space, required this.picture, required this.fallback});

  final SpaceService space;
  final SpacePicture? picture;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final p = picture;
    if (p == null) return fallback;
    return SecureImage(space: space, id: p.mediaId, thumb: p.media.thumb);
  }
}

// ===================================================================== photo du couple

/// La photo à deux, ronde ; un anneau dégradé l'entoure quand un instant attend d'être vu.
class CoupleAvatar extends StatelessWidget {
  const CoupleAvatar({super.key, required this.space, this.size = 78, this.ring = false, this.onTap});

  final SpaceService space;
  final double size;
  final bool ring;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final gap = size > 50 ? 3.0 : 2.0;
    final photo = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: PictureView(
          space: space,
          picture: space.avatar,
          fallback: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.secondary, cs.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Icon(Icons.favorite_rounded, color: Colors.white, size: size * .42),
            ),
          ),
        ),
      ),
    );
    final framed = Container(
      padding: EdgeInsets.all(gap),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ring ? context.love.ring(cs) : null,
        color: ring ? null : cs.surface,
      ),
      child: Container(
        padding: EdgeInsets.all(gap),
        decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface),
        child: photo,
      ),
    );
    return Semantics(
      button: onTap != null,
      label: ring ? 'Photo du couple, un instant à voir' : 'Photo du couple',
      child: GestureDetector(onTap: onTap, child: framed),
    );
  }
}

// ===================================================================== petits éléments

class LoveChip extends StatelessWidget {
  const LoveChip({super.key, required this.label, this.icon, this.muted = false, this.onTap});

  final String label;
  final IconData? icon;
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = muted ? context.cs.onSurfaceVariant : context.cs.primary;
    return Material(
      color: muted ? context.love.surface2 : context.love.soft,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
              Text(
                label,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: context.cs.onSurfaceVariant,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Carte arrondie, cliquable.
class LoveCard extends StatelessWidget {
  const LoveCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14), this.color});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Material(
    color: color ?? context.cs.surfaceContainer,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: context.cs.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// Petite tuile carrée à fond dégradé avec une icône.
class GlowIcon extends StatelessWidget {
  const GlowIcon(this.icon, {super.key, this.size = 44});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .32),
      gradient: LinearGradient(colors: [context.love.gold, context.cs.secondary]),
    ),
    child: Icon(icon, color: Colors.white, size: size * .5),
  );
}
