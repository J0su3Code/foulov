import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'chat_service.dart';
import 'seasons_screen.dart';
import '../dates/dates_screen.dart';

/// L'espace du couple, avec sa barre de navigation (Messages, Saisons, Dates). La barre ne montre que ce qui
/// fonctionne vraiment.
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      // Les écrans gardent leur état (défilement, saisie en cours) d'un onglet à l'autre.
      body: IndexedStack(
        index: _tab,
        children: [
          ChatScreen(
            service: widget.service,
            since: widget.since,
            onShowSymbols: widget.onShowSymbols,
            onSignOut: widget.onSignOut,
            // « Lu » seulement quand la conversation est vraiment sous les yeux.
            active: _tab == 0,
          ),
          SeasonsScreen(service: widget.service),
          DatesScreen(service: widget.service),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 66,
        backgroundColor: cs.surface,
        indicatorColor: cs.secondary.withValues(alpha: .28),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library_rounded),
            label: 'Saisons',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event_rounded),
            label: 'Dates',
          ),
        ],
      ),
    );
  }
}
