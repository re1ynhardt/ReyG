import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/post.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/posts_provider.dart';
import '../../utils/relative_time.dart';
import '../../widgets/artist_avatar.dart';
import '../../widgets/cached_cover_image.dart';
import '../community/user_profile_screen.dart';
import 'create_post_screen.dart';

/// Community posts feed. With no [authorId]/[hashtag] this is the global
/// feed (everyone's posts, newest first); pass [authorId] to show one
/// account's posts instead (opened from their Community profile), or
/// [hashtag] to filter the global feed to one tag (tapping a hashtag chip
/// re-opens this screen filtered to it).
class PostsFeedScreen extends StatefulWidget {
  const PostsFeedScreen({super.key, this.authorId, this.authorName, this.hashtag});

  final String? authorId;
  final String? authorName;
  final String? hashtag;

  @override
  State<PostsFeedScreen> createState() => _PostsFeedScreenState();
}

class _PostsFeedScreenState extends State<PostsFeedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<PostsProvider>().loadFeed(authorId: widget.authorId, hashtag: widget.hashtag),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posts = context.watch<PostsProvider>();
    final currentUserId = context.watch<AuthProvider>().user?.id;
    final showFab = widget.authorId == null || widget.authorId == currentUserId;
    final title = widget.authorName != null
        ? widget.authorName!
        : (widget.hashtag != null ? '#${widget.hashtag}' : context.tr('posts_feed_title'));

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: RefreshIndicator(
        onRefresh: () => context.read<PostsProvider>().loadFeed(authorId: widget.authorId, hashtag: widget.hashtag),
        child: posts.loading && posts.feed.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : posts.feed.isEmpty
                ? ListView(
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: Center(
                          child: Text(context.tr('no_posts_found'), style: TextStyle(color: Theme.of(context).hintColor)),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100, top: 8),
                    itemCount: posts.feed.length,
                    itemBuilder: (context, i) => _PostCard(post: posts.feed[i], currentUserId: currentUserId),
                  ),
      ),
      floatingActionButton: showFab
          ? Padding(
              padding: const EdgeInsets.only(bottom: 84),
              child: FloatingActionButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreatePostScreen())),
                child: const Icon(Icons.add),
              ),
            )
          : null,
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.currentUserId});

  final Post post;
  final String? currentUserId;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('post_delete')),
        content: Text(context.tr('post_delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('delete'))),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await context.read<PostsProvider>().deletePost(post.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final community = context.watch<CommunityProvider>();
    final author = community.userById(post.authorId);
    final library = context.watch<LibraryProvider>();
    final tracks = post.trackIds.map((id) => library.trackById(id)).whereType<Track>().toList();
    final posts = context.watch<PostsProvider>();
    final liked = posts.isLiked(post.id);
    final auth = context.read<AuthProvider>();
    final canDelete = post.authorId == currentUserId || auth.hasDeveloperRights;
    final accent = theme.colorScheme.secondary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24, tileMode: TileMode.mirror),
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.55),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: author == null
                            ? null
                            : () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => UserProfileScreen(user: author))),
                        child: ArtistAvatar(imageUrl: author?.avatarUrl ?? '', radius: 19),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              author?.displayName ?? '…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              formatRelativeTime(context, post.createdAt),
                              style: TextStyle(color: theme.hintColor, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (canDelete)
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 20, color: theme.hintColor),
                          tooltip: context.tr('post_delete'),
                          onPressed: () => _confirmDelete(context),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  if (post.text.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(post.text, style: const TextStyle(height: 1.3)),
                  ],
                  if (post.imageUrls.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _PostImages(urls: post.imageUrls),
                  ],
                  if (tracks.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (var i = 0; i < tracks.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      Material(
                        color: theme.scaffoldBackgroundColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => context.read<PlayerProvider>().playSingle(tracks[i]),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedCoverImage(track: tracks[i], width: 44, height: 44),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(tracks[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text(
                                        tracks[i].artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: theme.hintColor, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.play_circle_fill, color: accent),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (post.hashtags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: post.hashtags
                          .map((tag) => Material(
                                color: accent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => PostsFeedScreen(hashtag: tag)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    child: Text(
                                      '#$tag',
                                      style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => context.read<PostsProvider>().toggleLike(post.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                                  child: Icon(
                                    liked ? Icons.favorite : Icons.favorite_border,
                                    key: ValueKey(liked),
                                    color: liked ? Colors.redAccent : theme.hintColor,
                                    size: 21,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${post.likeCount}',
                                  style: TextStyle(
                                    color: liked ? Colors.redAccent : theme.hintColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          formatAbsoluteDate(post.createdAt),
                          style: TextStyle(color: theme.hintColor.withOpacity(0.8), fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PostImages extends StatelessWidget {
  const _PostImages({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = urls.length == 1 ? 1 : 2;
    const spacing = 4.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final cellHeight = urls.length == 1 ? cellWidth * 10 / 16 : cellWidth;
        final rows = (urls.length / crossAxisCount).ceil();
        final totalHeight = rows * cellHeight + (rows - 1) * spacing;
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: totalHeight,
            child: GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: urls.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childAspectRatio: cellWidth / cellHeight,
              ),
              itemBuilder: (context, i) => CachedNetworkImage(
                imageUrl: urls[i],
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: Theme.of(context).cardColor,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
