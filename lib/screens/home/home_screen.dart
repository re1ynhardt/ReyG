import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../providers/messages_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/api_service.dart';
import '../../services/message_notification_service.dart';
import '../../services/update_service.dart';
import '../../widgets/update_prompt.dart';
import '../community/community_screen.dart';
import '../library/library_screen.dart';
import '../messages/messages_screen.dart';
import '../player/mini_player.dart';
import '../posts/posts_feed_screen.dart';
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
    PostsFeedScreen(),
    LibraryScreen(),
    CommunityScreen(),
    MessagesScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Silent, best-effort check — shows a dialog only if a newer build
    // exists, says nothing otherwise (see checkForUpdatesAndPrompt).
    // Deferred to after the first frame so it never competes with the
    // screen's own startup work, and doesn't run again on tab switches
    // since this state persists for the app's lifetime.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      checkForUpdatesAndPrompt(context, service: context.read<UpdateService>());
      // Best-effort: populates the unread badge on the messages nav item
      // without requiring the user to open that tab first.
      context.read<MessagesProvider>().loadConversations();

      // Phone notifications for new incoming DMs — see
      // lib/services/message_notification_service.dart for why this is a
      // local-notification poll rather than a real FCM/APNs push.
      final myId = context.read<AuthProvider>().user?.id;
      if (myId == null) return;
      final community = context.read<CommunityProvider>();
      if (community.users.isEmpty) unawaited(community.loadUsers());
      await MessageNotificationService.instance.init();
      if (!mounted) return;
      MessageNotificationService.instance.start(
        context.read<ApiService>(),
        myId,
        displayNameOf: (otherUserId) {
          for (final u in community.users) {
            if (u.id == otherUserId) return u.displayName;
          }
          return 'Новое сообщение';
        },
      );
    });
  }

  @override
  void dispose() {
    MessageNotificationService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasTrack = context.select<PlayerProvider, bool>((p) => p.hasTrack);
    final unreadMessages = context.select<MessagesProvider, int>((p) => p.unreadCount);

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
              AppNavItem(icon: Icons.dynamic_feed_outlined, activeIcon: Icons.dynamic_feed, label: context.tr('feed')),
              AppNavItem(icon: Icons.library_music_outlined, activeIcon: Icons.library_music, label: context.tr('library')),
              AppNavItem(icon: Icons.groups_outlined, activeIcon: Icons.groups, label: context.tr('community')),
              AppNavItem(
                icon: Icons.chat_bubble_outline,
                activeIcon: Icons.chat_bubble,
                label: context.tr('messages'),
                badgeCount: unreadMessages,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
