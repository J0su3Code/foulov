import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/foulov_theme.dart';
import '../space/letters_screen.dart';
import '../space/nous_screen.dart';
import '../space/souvenirs_screen.dart';
import 'chat_screen.dart';
import 'chat_service.dart';

/// L'espace du couple et sa barre de navigation : Nous · Messages · Souvenirs · Lettres.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.service,
    required this.since,
    required this.onShowSymbols,
    required this.onSignOut,
  });

  final ChatService service;
  final DateTime? since;
  final VoidCallback onShowSymbols;
  final VoidCallback onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  DateTime? _backAt;

  void _go(int i) {
    if (i == _tab || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return PopScope(
      // Retour depuis un autre onglet : on revient à « Nous ». Depuis « Nous » : un premier retour prévient,
      // un second (dans les 2 s) ferme FouLove.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tab != 0) {
          _go(0);
          return;
        }
        final now = DateTime.now();
        if (_backAt != null && now.difference(_backAt!) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _backAt = now;
        HapticFeedback.selectionClick();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Appuie encore une fois pour quitter FouLove'),
              duration: Duration(seconds: 2),
            ),
          );
      },
      child: Scaffold(
        // Les écrans gardent leur état (défilement, saisie en cours) d'un onglet à l'autre.
        body: IndexedStack(
          index: _tab,
          children: [
            NousScreen(
              chat: s,
              onOpenChat: () => _go(1),
              onOpenLetters: () => _go(3),
              onShowSymbols: widget.onShowSymbols,
              onSignOut: widget.onSignOut,
            ),
            ChatScreen(
              service: s,
              since: widget.since,
              onShowSymbols: widget.onShowSymbols,
              onSignOut: widget.onSignOut,
              // « Lu » seulement quand la conversation est vraiment sous les yeux.
              active: _tab == 1,
              onBack: () => _go(0),
              bottomInset: MediaQuery.paddingOf(context).bottom,
            ),
            SouvenirsScreen(chat: s),
            LettersScreen(chat: s),
          ],
        ),
        // Dans la conversation, la barre s'efface : tout le bas est pour la saisie, comme dans une messagerie.
        bottomNavigationBar: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: _tab == 1
              ? const SizedBox(width: double.infinity)
              : ListenableBuilder(
                  listenable: Listenable.merge([s, s.space]),
                  builder: (context, _) {
                    final unread = s.messages.where((m) => !m.fromMe && m.status == 0 && !m.deleted).length;
                    return _LoveBar(
                      index: _tab,
                      onTap: _go,
                      items: [
                        const _Item(Icons.favorite_border_rounded, Icons.favorite_rounded, 'Nous'),
                        _Item(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Messages', badge: unread),
                        const _Item(Icons.photo_library_outlined, Icons.photo_library_rounded, 'Souvenirs'),
                        _Item(Icons.mail_outline_rounded, Icons.mail_rounded, 'Lettres', badge: s.space.unreadLetters),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _Item {
  const _Item(this.icon, this.selected, this.label, {this.badge = 0});

  final IconData icon, selected;
  final String label;
  final int badge;
}

/// Barre du bas : pastille douce sous l'onglet actif, pastille rose pour ce qui attend.
class _LoveBar extends StatelessWidget {
  const _LoveBar({required this.index, required this.onTap, required this.items});

  final int index;
  final ValueChanged<int> onTap;
  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              for (final (i, it) in items.indexed)
                Expanded(
                  child: Semantics(
                    selected: i == index,
                    button: true,
                    label: it.badge > 0 ? '${it.label}, ${it.badge} nouveau${it.badge > 1 ? 'x' : ''}' : it.label,
                    child: InkResponse(
                      onTap: () => onTap(i),
                      radius: 40,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                padding: EdgeInsets.symmetric(horizontal: i == index ? 20 : 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: i == index ? context.love.soft : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  i == index ? it.selected : it.icon,
                                  color: i == index ? cs.primary : cs.onSurfaceVariant,
                                  size: 24,
                                ),
                              ),
                              if (it.badge > 0)
                                Positioned(
                                  right: i == index ? 8 : 2,
                                  top: -2,
                                  child: Container(
                                    constraints: const BoxConstraints(minWidth: 17),
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: cs.surface, width: 1.5),
                                    ),
                                    child: Text(
                                      it.badge > 99 ? '99+' : '${it.badge}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: cs.onPrimary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            it.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                              color: i == index ? cs.onSurface : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
