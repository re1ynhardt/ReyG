import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../providers/player_provider.dart';
import '../library/library_screen.dart';
import '../player/mini_player.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import 'home_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  final _tabs = const [
    HomeTab(),
    SearchScreen(),
    LibraryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final hasTrack = context.watch<PlayerProvider>().hasTrack;

    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasTrack) Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: const MiniPlayer(),
          ),
          BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            items: [
              BottomNavigationBarItem(icon: const Icon(Icons.home_filled), label: context.tr('home')),
              BottomNavigationBarItem(icon: const Icon(Icons.search), label: context.tr('search')),
              BottomNavigationBarItem(icon: const Icon(Icons.library_music), label: context.tr('library')),
              BottomNavigationBarItem(icon: const Icon(Icons.settings), label: context.tr('settings')),
            ],
          ),
        ],
      ),
    );
  }
}
