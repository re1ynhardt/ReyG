import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../widgets/artist_avatar.dart';
import '../../widgets/section_header.dart';
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
    final favoriteCount = users.where((u) => community.isFavoriteUser(u.id)).length;
    final currentUserId = context.watch<AuthProvider>().user?.id;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('community'))),
      body: RefreshIndicator(
        onRefresh: () => context.read<CommunityProvider>().loadUsers(),
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
                  // group to separate from the rest of the list.
                  itemCount: users.length + (favoriteCount > 0 && favoriteCount < users.length ? 2 : 0),
                  itemBuilder: (context, i) {
                    final showHeaders = favoriteCount > 0 && favoriteCount < users.length;
                    if (!showHeaders) {
                      return _UserTile(user: users[i], currentUserId: currentUserId);
                    }
                    if (i == 0) {
                      return SectionHeader(title: context.tr('favorite_users_section'), topSpacing: 4);
                    }
                    if (i == favoriteCount + 1) {
                      return SectionHeader(title: context.tr('all_users_section'));
                    }
                    final userIndex = i < favoriteCount + 1 ? i - 1 : i - 2;
                    return _UserTile(user: users[userIndex], currentUserId: currentUserId);
                  },
                ),
              ),
          ],
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
          if (user.isDeveloper)
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
                  Icons.verified,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
      title: Text(user.displayName),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (user.isDeveloper)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                label: Text(context.tr('developer_account')),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          if (!isSelf)
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
      ),
    );
  }
}
