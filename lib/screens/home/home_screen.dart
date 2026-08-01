import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../providers/player_provider.dart';
import '../../services/update_service.dart';
import '../../widgets/update_prompt.dart';
import '../community/community_screen.dart';
import '../library/library_screen.dart';
import '../player/mini_player.dart';
import '../search/search_screen.dart';
import '../../widgets/app_bottom_nav_bar.dart';
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
    CommunityScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Silent, best-effort check — shows a dialog only if a newer build
    // exists, says nothing otherwise (see checkForUpdatesAndPrompt).
    // Deferred to after the first frame so it never competes with the
    // screen's own startup work, and doesn't run again on tab switches
    // since this state persists for the app's lifetime.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      checkForUpdatesAndPrompt(context, service: context.read<UpdateService>());
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasTrack = context.select<PlayerProvider, bool>((p) => p.hasTrack);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasTrack) Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: const MiniPlayer(),
          ),
          AppBottomNavBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            items: [
              AppNavItem(icon: Icons.home_outlined, activeIcon: Icons.home_filled, label: context.tr('home')),
              AppNavItem(icon: Icons.search, activeIcon: Icons.search, label: context.tr('search')),
              AppNavItem(icon: Icons.library_music_outlined, activeIcon: Icons.library_music, label: context.tr('library')),
              AppNavItem(icon: Icons.groups_outlined, activeIcon: Icons.groups, label: context.tr('community')),
            ],
          ),
        ],
      ),
    );
  }
}
