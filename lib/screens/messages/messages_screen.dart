import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/message.dart';
import '../../providers/app_state.dart';
import '../../providers/community_provider.dart';
import '../../providers/messages_provider.dart';
import '../../widgets/artist_avatar.dart';
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
                      return _ConversationTile(convo: convo, displayName: user?.displayName, avatarUrl: user?.avatarUrl);
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
  const _ConversationTile({required this.convo, required this.displayName, required this.avatarUrl});

  final ConversationSummary convo;
  final String? displayName;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = displayName ?? convo.otherUserId;
    final preview = convo.lastMessageFromMe ? '${context.tr('you_prefix')}${convo.lastMessage}' : convo.lastMessage;
    return ListTile(
      leading: ArtistAvatar(imageUrl: avatarUrl ?? '', radius: 24),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.hintColor)),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserId: convo.otherUserId,
          otherUserDisplayName: name,
          otherUserAvatarUrl: avatarUrl ?? '',
        ),
      )),
    );
  }
}
