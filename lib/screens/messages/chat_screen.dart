import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/message_attachment.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../providers/messages_provider.dart';
import '../../providers/player_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/duration_format.dart';
import '../../widgets/artist_avatar.dart';
import '../../widgets/cached_cover_image.dart';
import '../../widgets/message_read_ticks.dart';
import '../community/user_profile_screen.dart';
import 'attach_picker_sheet.dart';
import 'attachment_playlist_sheet.dart';
import '../player/mini_player.dart';

/// One DM thread between the signed-in account and [otherUserId]. Opened
/// either from the Messages tab's conversation list or from a Community
/// profile's Message button. On the real backend, messages are
/// end-to-end encrypted in transit and at rest (see
/// `YandexStorageApiService`'s Messages section) — this screen only
/// ever sees plaintext, already decrypted.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserDisplayName,
    required this.otherUserAvatarUrl,
  });

  final String otherUserId;
  final String otherUserDisplayName;
  final String otherUserAvatarUrl;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  MessageAttachment? _pendingAttachment;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final community = context.read<CommunityProvider>();
      if (community.users.isEmpty) community.loadUsers();
      await context.read<MessagesProvider>().loadThread(widget.otherUserId);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: false));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(target);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final pending = _pendingAttachment;
    if (pending == null && text.isEmpty) return;

    final messageText = pending != null ? pending.withCaption(text).encode() : text;
    _controller.clear();
    setState(() => _pendingAttachment = null);
    try {
      await context.read<MessagesProvider>().send(otherUserId: widget.otherUserId, text: messageText);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      _controller.text = text;
      setState(() => _pendingAttachment = pending);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openAttachPicker() async {
    final attachment = await showModalBottomSheet<MessageAttachment>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AttachPickerSheet(),
    );
    if (attachment == null || !mounted) return;
    setState(() => _pendingAttachment = attachment);
  }

  @override
  Widget build(BuildContext context) {
    final messagesProvider = context.watch<MessagesProvider>();
    final messages = messagesProvider.messagesWith(widget.otherUserId);
    final loading = messagesProvider.loadingThread;
    final myId = context.watch<AuthProvider>().user?.id;
    final otherUser = context.watch<CommunityProvider>().userById(widget.otherUserId);
    final hasTrack = context.select<PlayerProvider, bool>((p) => p.hasTrack);
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            GestureDetector(
              onTap: otherUser == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => UserProfileScreen(user: otherUser)),
                      ),
              child: ArtistAvatar(imageUrl: widget.otherUserAvatarUrl, radius: 16),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.otherUserDisplayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (hasTrack)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: const MiniPlayer(),
            ),
          Expanded(
            child: loading && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? Center(
                        child: Text(
                          context.tr('no_messages_in_chat'),
                          style: TextStyle(color: theme.hintColor),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final isMine = message.senderId == myId;
                          final attachment = MessageAttachment.tryParse(message.text);
                          return Align(
                            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  if (attachment != null)
                                    ConstrainedBox(
                                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                      child: _AttachmentBubble(attachment: attachment, isMine: isMine),
                                    )
                                  else
                                    Container(
                                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isMine ? accent : theme.cardColor,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: Radius.circular(isMine ? 16 : 4),
                                        bottomRight: Radius.circular(isMine ? 4 : 16),
                                      ),
                                    ),
                                    child: Text(
                                      message.text,
                                      style: TextStyle(color: isMine ? onColor(accent) : theme.colorScheme.onSurface),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: -6,
                                    right: isMine ? -6 : null,
                                    left: isMine ? null : -6,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: theme.scaffoldBackgroundColor,
                                        border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                                      ),
                                      child: MessageReadTicks(
                                        read: isMine
                                            ? messagesProvider.isReadByOther(widget.otherUserId, message.createdAt)
                                            : true,
                                        size: 11,
                                        readColor: theme.colorScheme.secondary,
                                        unreadColor: theme.hintColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_pendingAttachment != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PendingAttachmentPreview(
                        attachment: _pendingAttachment!,
                        onRemove: () => setState(() => _pendingAttachment = null),
                      ),
                    ),
                  Row(
                children: [
                  Material(
                    color: theme.cardColor,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _openAttachPicker,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.add, size: 20, color: theme.hintColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: context.tr('message_hint'),
                        filled: true,
                        fillColor: theme.cardColor,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: accent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _send,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.send, size: 20, color: onColor(accent)),
                      ),
                    ),
                  ),
                ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small strip shown above the composer while a track/playlist is staged
/// via the attach (+) button — lets the person see what they picked, type
/// an optional caption alongside it, and back out before sending.
class _PendingAttachmentPreview extends StatelessWidget {
  const _PendingAttachmentPreview({required this.attachment, required this.onRemove});
  final MessageAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: attachment.isTrack
                  ? CachedCoverImage(
                      track: attachment.toTrack(),
                      width: 36,
                      height: 36,
                      errorBuilder: (_) => Container(width: 36, height: 36, color: theme.scaffoldBackgroundColor),
                    )
                  : (attachment.coverUrl.isEmpty
                      ? Container(
                          width: 36,
                          height: 36,
                          color: theme.scaffoldBackgroundColor,
                          child: const Icon(Icons.queue_music, size: 18),
                        )
                      : Image.network(
                          attachment.coverUrl,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(width: 36, height: 36, color: theme.scaffoldBackgroundColor),
                        )),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.isTrack ? context.tr('attach_track_tab') : context.tr('attach_playlist_tab'),
                    style: TextStyle(color: theme.hintColor, fontSize: 11),
                  ),
                  Text(
                    attachment.isTrack ? attachment.title : attachment.playlistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              splashRadius: 18,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a track or playlist attachment as a small card inside the chat
/// bubble. Tapping a track plays it immediately; tapping a playlist opens
/// [AttachmentPlaylistSheet] to browse/play it.
class _AttachmentBubble extends StatelessWidget {
  const _AttachmentBubble({required this.attachment, required this.isMine});
  final MessageAttachment attachment;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = isMine ? onColor(theme.colorScheme.secondary) : theme.colorScheme.onSurface;
    return Material(
      color: isMine ? theme.colorScheme.secondary : theme.cardColor,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: Radius.circular(isMine ? 16 : 4),
        bottomRight: Radius.circular(isMine ? 4 : 16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (attachment.isTrack) {
            context.read<PlayerProvider>().playSingle(attachment.toTrack());
          } else {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => AttachmentPlaylistSheet(attachment: attachment),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: attachment.isTrack
                    ? CachedCoverImage(
                        track: attachment.toTrack(),
                        width: 48,
                        height: 48,
                        errorBuilder: (_) => _fallbackArt(theme),
                      )
                    : (attachment.coverUrl.isEmpty
                        ? _fallbackArt(theme, icon: Icons.queue_music)
                        : Image.network(
                            attachment.coverUrl,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fallbackArt(theme, icon: Icons.queue_music),
                          )),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.isTrack ? attachment.title : attachment.playlistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      attachment.isTrack
                          ? '${attachment.artist} · ${formatDuration(Duration(seconds: attachment.durationSeconds))}'
                          : '${attachment.trackIds.length} ${context.tr('stat_tracks').toLowerCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foreground.withOpacity(0.75), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(attachment.isTrack ? Icons.play_circle_fill : Icons.chevron_right, color: foreground, size: 26),
                ],
              ),
              if (attachment.caption.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    attachment.caption,
                    style: TextStyle(color: foreground),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackArt(ThemeData theme, {IconData icon = Icons.music_note}) => Container(
        width: 48,
        height: 48,
        color: theme.scaffoldBackgroundColor,
        child: Icon(icon, size: 20),
      );
}
