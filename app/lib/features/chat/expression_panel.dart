import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../src/rust/api/chat.dart';
import 'stickers.dart';

/// Le panneau du bouton smiley, comme WhatsApp : **Émojis** et **Stickers**, en onglets en bas.
/// Il s'ouvre sur l'onglet utilisé la dernière fois (les émojis la première fois).
class ExpressionPanel extends StatefulWidget {
  const ExpressionPanel({
    super.key,
    required this.height,
    required this.input,
    required this.onSticker,
    this.bottomInset = 0,
  });

  final double height;

  /// Barre de gestes du système, sous le panneau.
  final double bottomInset;

  /// Champ de saisie de la conversation : les émojis s'y insèrent à l'endroit du curseur.
  final TextEditingController input;
  final void Function(Sticker sticker, Uint8List bytes) onSticker;

  @override
  State<ExpressionPanel> createState() => _ExpressionPanelState();
}

class _ExpressionPanelState extends State<ExpressionPanel> {
  /// Dernier onglet utilisé, gardé le temps que l'app est ouverte (0 émojis, 1 stickers).
  static int _last = 0;

  static const _bar = 48.0;

  void _go(int i) {
    if (i == _last) return;
    HapticFeedback.selectionClick();
    setState(() => _last = i);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = widget.height - _bar - widget.bottomInset;
    return Container(
      height: widget.height,
      color: cs.surfaceContainer,
      child: Column(
        children: [
          SizedBox(
            height: body,
            child: IndexedStack(
              index: _last,
              children: [
                EmojiPicker(
                  textEditingController: widget.input,
                  onBackspacePressed: () {},
                  config: Config(
                    height: body,
                    locale: const Locale('fr'),
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      columns: 8,
                      emojiSizeMax: 30,
                      backgroundColor: cs.surfaceContainer,
                      noRecents: Text(
                        'Tes émojis récents apparaîtront ici',
                        style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                      ),
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      initCategory: Category.SMILEYS,
                      backgroundColor: cs.surfaceContainer,
                      indicatorColor: cs.primary,
                      iconColor: cs.onSurfaceVariant,
                      iconColorSelected: cs.primary,
                      backspaceColor: cs.primary,
                      dividerColor: cs.outline,
                    ),
                    bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
                    skinToneConfig: const SkinToneConfig(),
                    searchViewConfig: SearchViewConfig(backgroundColor: cs.surfaceContainer),
                  ),
                ),
                StickerPanel(height: body, onSend: widget.onSticker),
              ],
            ),
          ),
          Container(
            height: _bar,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outline))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Tab(icon: Icons.emoji_emotions_outlined, label: 'Émojis', on: _last == 0, onTap: () => _go(0)),
                const SizedBox(width: 12),
                _Tab(icon: Icons.sticky_note_2_outlined, label: 'Stickers', on: _last == 1, onTap: () => _go(1)),
              ],
            ),
          ),
          SizedBox(height: widget.bottomInset),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.on, required this.onTap});

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = on ? cs.primary : cs.onSurfaceVariant;
    return Semantics(
      selected: on,
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: on ? cs.primary.withValues(alpha: .12) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
