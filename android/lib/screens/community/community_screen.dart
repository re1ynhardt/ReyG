import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../widgets/artist_avatar.dart';
import '../../widgets/section_header.dart';
import '../messages/chat_screen.dart';
import '../posts/posts_feed_screen.dart';
import 'user_profile_screen.dart';

/// Community tab: every registered user, searchable by name, with a small
/// badge marking developer accounts.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final _controller = TextEditingController();
  bool _requested = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final community = context.watch<CommunityProvider>();

    // Kick off the initial load lazily the first time this tab is actually
    // built, same as other tabs that fetch on demand rather than eagerly
    // at app startup.
    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => context.read<CommunityProvider>().loadUsers());
    }

    final users = community.users;
    final currentUserId = context.watch<AuthProvider>().user?.id;

    // Pull the signed-in user's own entry out so it can always be pinned
    // to the very top of the list, above the favorites/all-users groups.
    AppUser? selfUser;
    final others = <AppUser>[];
    for (final u in users) {
      if (currentUserId != null && u.id == currentUserId) {
        selfUser = u;
      } else {
        others.add(u);
      }
    }
    final hasSelf = selfUser != null;
    final favoriteCount = others.where((u) => community.isFavoriteUser(u.id)).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('community')),
        actions: [
          IconButton(
            icon: const Icon(Icons.dynamic_feed_outlined),
            tooltip: context.tr('posts'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PostsFeedScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<CommunityProvider>().loadUsers(forceRefresh: true),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _controller,
                onChanged: (q) => context.read<CommunityProvider>().search(q),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: context.tr('search_users_hint'),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _controller.clear();
                            context.read<CommunityProvider>().search('');
                            setState(() {});
                          },
                        ),
                ),
                onSubmitted: (_) => setState(() {}),
              ),
            ),
            if (hasSelf) _SelfProfileCard(user: selfUser!),
            if (community.loading && users.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (users.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    context.tr('no_users_found'),
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  // +2 optional header rows when there's a favorites
                  // group to separate from the rest of the (self-
                  // excluded) list.
                  itemCount: others.length + (favoriteCount > 0 && favoriteCount < others.length ? 2 : 0),
                  itemBuilder: (context, i) {
                    final showHeaders = favoriteCount > 0 && favoriteCount < others.length;
                    if (!showHeaders) {
                      return _UserTile(user: others[i], currentUserId: currentUserId);
                    }
                    if (i == 0) {
                      return SectionHeader(title: context.tr('favorite_users_section'), topSpacing: 4);
                    }
                    if (i == favoriteCount + 1) {
                      return SectionHeader(title: context.tr('all_users_section'));
                    }
                    final userIndex = i < favoriteCount + 1 ? i - 1 : i - 2;
                    return _UserTile(user: others[userIndex], currentUserId: currentUserId);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Frosted-glass card that always sits above the rest of the Community
/// list, pinned outside the scrolling list itself so it reads as a
/// separate "you" section rather than just another row. Tapping it opens
/// the same read-only profile screen as everyone else's tile.
class _SelfProfileCard extends StatelessWidget {
  const _SelfProfileCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => UserProfileScreen(user: user)),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary.withOpacity(0.16),
                      theme.colorScheme.secondary.withOpacity(0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: theme.colorScheme.primary.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ArtistAvatar(imageUrl: user.avatarUrl, radius: 24),
                        if (user.isDeveloper || user.isSupport || user.isPerformer)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(1.5),
                              decoration: BoxDecoration(
                                color: theme.scaffoldBackgroundColor,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                (user.isDeveloper || user.isSupport) ? Icons.verified : Icons.mic,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.tr('your_profile_section'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: theme.hintColor),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.currentUserId});

  final AppUser user;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final community = context.watch<CommunityProvider>();
    final isFavorite = community.isFavoriteUser(user.id);
    final isSelf = currentUserId != null && currentUserId == user.id;

    return ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => UserProfileScreen(user: user)),
      ),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          ArtistAvatar(imageUrl: user.avatarUrl, radius: 22),
          if (user.isDeveloper || user.isSupport || user.isPerformer)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  (user.isDeveloper || user.isSupport) ? Icons.verified : Icons.mic,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
      title: Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (user.isDeveloper || user.isSupport || user.isPerformer)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                label: Text(
                  user.isDeveloper
                      ? context.tr('developer_account')
                      : user.isSupport
                          ? context.tr('support_account')
                          : context.tr('performer_account'),
                  style: const TextStyle(fontSize: 10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          if (!isSelf) ...[
            IconButton(
              icon: const Icon(Icons.mail_outline),
              tooltip: context.tr('profile_message'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChatScreen(
                  otherUserId: user.id,
                  otherUserDisplayName: user.displayName,
                  otherUserAvatarUrl: user.avatarUrl,
                ),
              )),
            ),
            IconButton(
              icon: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: isFavorite ? Colors.amber : Theme.of(context).hintColor,
              ),
              tooltip: isFavorite
                  ? context.tr('remove_user_from_favorites')
                  : context.tr('add_user_to_favorites'),
              onPressed: () => context.read<CommunityProvider>().toggleFavoriteUser(user.id),
            ),
          ],
        ],
      ),
    );
  }
}
