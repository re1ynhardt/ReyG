import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../providers/app_state.dart';
import '../../providers/community_provider.dart';
import '../../providers/messages_provider.dart';
import '../../widgets/artist_avatar.dart';
import '../../widgets/message_read_ticks.dart';
import '../community/user_profile_screen.dart';
import 'chat_screen.dart';

/// List of the signed-in account's DM conversations. Opened from the
/// "messenger" icon in the bottom nav, and from a Community profile's
/// Message button (which opens straight into [ChatScreen] instead).
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    final messages = context.watch<MessagesProvider>();
    final community = context.watch<CommunityProvider>();

    // Kick off both loads lazily the first time this tab is actually
    // built, same pattern the Community tab uses.
    if (!_requested) {
      _requested = true;
      Future.microtask(() {
        messages.loadConversations();
        if (community.users.isEmpty) community.loadUsers();
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('messages'))),
      body: RefreshIndicator(
        onRefresh: messages.loadConversations,
        child: messages.loadingConversations && messages.conversations.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : messages.conversations.isEmpty
                ? _EmptyState(hint: context.tr('no_messages_yet'))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: messages.conversations.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                    itemBuilder: (context, index) {
                      final convo = messages.conversations[index];
                      final user = community.userById(convo.otherUserId);
                      return _ConversationTile(
                        convo: convo,
                        user: user,
                        unread: messages.isUnread(convo),
                        readByOther: convo.lastMessageFromMe
                            ? messages.isReadByOther(convo.otherUserId, convo.lastMessageAt)
                            : false,
                      );
                    },
                  ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline, size: 56, color: theme.hintColor),
                const SizedBox(height: 16),
                Text(hint, textAlign: TextAlign.center, style: TextStyle(color: theme.hintColor)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.convo,
    required this.user,
    required this.unread,
    required this.readByOther,
  });

  final ConversationSummary convo;
  final AppUser? user;

  /// True when the latest message is an unread incoming one from them.
  final bool unread;

  /// True when the latest message is one I sent and they've read it.
  /// Meaningless (and unused) when the latest message is from them.
  final bool readByOther;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = user?.displayName ?? convo.otherUserId;
    final avatarUrl = user?.avatarUrl ?? '';
    final preview = convo.lastMessageFromMe ? '${context.tr('you_prefix')}${convo.lastMessage}' : convo.lastMessage;
    return ListTile(
      leading: GestureDetector(
        onTap: user == null ? null : () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => UserProfileScreen(user: user!)),
            ),
        child: ArtistAvatar(imageUrl: avatarUrl, radius: 24),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600),
      ),
      subtitle: Row(
        children: [
          if (convo.lastMessageFromMe) ...[
            MessageReadTicks(read: readByOther, size: 14),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: unread ? theme.colorScheme.onSurface : theme.hintColor,
                fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
      trailing: unread ? const UnreadDot() : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserId: convo.otherUserId,
          otherUserDisplayName: name,
          otherUserAvatarUrl: avatarUrl,
        ),
      )),
    );
  }
}
