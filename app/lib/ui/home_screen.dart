import 'package:flutter/material.dart';

import '../data/models.dart';
import 'labels.dart';
import 'matches/match_list_screen.dart';
import 'matches/my_matches_screen.dart';
import 'profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.profile, required this.onProfileChanged});

  final Profile profile;
  final VoidCallback onProfileChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          MatchListScreen(profile: widget.profile),
          MyMatchesScreen(profile: widget.profile),
          ProfileScreen(profile: widget.profile, onChanged: widget.onProfileChanged),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.sports_soccer), label: l.tabMatches),
          NavigationDestination(icon: const Icon(Icons.event), label: l.tabMyMatches),
          NavigationDestination(icon: const Icon(Icons.person), label: l.tabProfile),
        ],
      ),
    );
  }
}
