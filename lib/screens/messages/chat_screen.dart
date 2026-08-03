import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
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
  Timer? _pollTimer;

  // Voice-message recording (see _startRecording/_stopAndSendRecording).
  // The recorded file never leaves the device unencrypted — it's
  // encrypted in MessagesProvider.uploadVoiceAttachment before upload.
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isUploadingVoice = false;
  DateTime? _recordingStartedAt;
  Timer? _recordTicker;
  Duration _recordingElapsed = Duration.zero;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final community = context.read<CommunityProvider>();
      if (community.users.isEmpty) community.loadUsers();
      // Not awaited: loadThread shows any cached messages the moment it has
      // them (see MessagesProvider.loadThread), and the reverse ListView
      // below is already anchored at the latest message, so the thread
      // opens instantly instead of waiting on the network fetch.
      context.read<MessagesProvider>().loadThread(widget.otherUserId);
    });
    // There's no realtime push from the backend, so poll for new incoming
    // messages while this thread is open (quiet refresh — no spinner, only
    // updates the UI when something actually changed).
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      context.read<MessagesProvider>().refreshThreadQuietly(widget.otherUserId);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _recordTicker?.cancel();
    _recorder.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // The message list is reversed (newest first, rendered bottom-up), so
  // "scroll to bottom" is scrolling to offset 0.
  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    if (animate) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final pending = _pendingAttachment;
    if (pending == null && text.isEmpty) return;

    final messageText = pending != null ? pending.withCaption(text).encode() : text;
    final myId = context.read<AuthProvider>().user?.id;
    if (myId == null) return;
    _controller.clear();
    setState(() => _pendingAttachment = null);
    try {
      await context.read<MessagesProvider>().send(otherUserId: widget.otherUserId, text: messageText, myId: myId);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      _controller.text = text;
      setState(() => _pendingAttachment = pending);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isUploadingVoice) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('mic_permission_denied'))));
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recordingPath = path;
      _recordingStartedAt = DateTime.now();
      _recordingElapsed = Duration.zero;
    });
    _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordingElapsed = DateTime.now().difference(_recordingStartedAt!));
    });
  }

  Future<void> _cancelRecording() async {
    _recordTicker?.cancel();
    final path = await _recorder.stop();
    if (mounted) setState(() => _isRecording = false);
    final toDelete = path ?? _recordingPath;
    if (toDelete != null) {
      try {
        await File(toDelete).delete();
      } catch (_) {
        // Best-effort — a leftover temp file isn't worth surfacing.
      }
    }
  }

  Future<void> _stopAndSendRecording() async {
    _recordTicker?.cancel();
    final path = await _recorder.stop();
    final elapsed = _recordingElapsed;
    if (mounted) setState(() => _isRecording = false);
    if (path == null || elapsed.inSeconds < 1) {
      // Too short to be a real message (e.g. an accidental tap) —
      // discard silently rather than sending a near-empty recording.
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      return;
    }
    final myId = context.read<AuthProvider>().user?.id;
    if (myId == null) return;
    setState(() => _isUploadingVoice = true);
    try {
      final attachment = await context.read<MessagesProvider>().uploadVoiceAttachment(
            path,
            recipientId: widget.otherUserId,
            durationSeconds: elapsed.inSeconds,
          );
      await context
          .read<MessagesProvider>()
          .send(otherUserId: widget.otherUserId, text: attachment.encode(), myId: myId);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
      if (mounted) setState(() => _isUploadingVoice = false);
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
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[messages.length - 1 - index];
                          final isMine = message.senderId == myId;
                          final attachment = MessageAttachment.tryParse(message.text);
                          final pending = isMine && messagesProvider.isPending(message.id);
                          return Align(
                            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Opacity(
                                opacity: pending ? 0.6 : 1,
                                child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  if (attachment != null)
                                    ConstrainedBox(
                                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                      child: _AttachmentBubble(
                                        attachment: attachment,
                                        isMine: isMine,
                                        otherUserId: widget.otherUserId,
                                      ),
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
                                      child: isMine && messagesProvider.isPending(message.id)
                                          ? Icon(Icons.access_time_rounded, size: 11, color: theme.hintColor)
                                          : MessageReadTicks(
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
                  if (_isRecording)
                    _RecordingBar(
                      elapsed: _recordingElapsed,
                      onCancel: _cancelRecording,
                      onSend: _stopAndSendRecording,
                    )
                  else if (_isUploadingVoice)
                    _UploadingVoiceBar(theme: theme)
                  else ...[
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
                          color: theme.cardColor,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _startRecording,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(Icons.mic_none_rounded, size: 20, color: theme.hintColor),
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
/// Replaces the composer while a voice message is being recorded — live
/// elapsed time, a cancel (discard) button, and a send button that stops
/// the recording and hands it off for upload (see
/// ChatScreen._stopAndSendRecording).
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({required this.elapsed, required this.onCancel, required this.onSend});
  final Duration elapsed;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
          const SizedBox(width: 8),
          Text(
            formatDuration(elapsed),
            style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            onPressed: onCancel,
            icon: Icon(Icons.delete_outline, color: theme.hintColor),
            tooltip: context.tr('cancel'),
          ),
          Material(
            color: accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onSend,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.send, size: 18, color: onColor(accent)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Replaces the composer while a just-recorded voice message is being
/// encrypted and uploaded (see ChatScreen._stopAndSendRecording) — the
/// composer would otherwise sit idle for the round-trip.
class _UploadingVoiceBar extends StatelessWidget {
  const _UploadingVoiceBar({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text(context.tr('sending_voice_message'), style: TextStyle(color: theme.hintColor)),
        ],
      ),
    );
  }
}

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
                    attachment.isTrack
                        ? context.tr('attach_track_tab')
                        : attachment.isImage
                            ? context.tr('attach_image_tab')
                            : context.tr('attach_playlist_tab'),
                    style: TextStyle(color: theme.hintColor, fontSize: 11),
                  ),
                  if (!attachment.isImage)
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

/// Renders a track, playlist, or image attachment inside the chat bubble.
/// Tapping a track plays it immediately; tapping a playlist opens
/// [AttachmentPlaylistSheet] to browse/play it; tapping an image opens it
/// full-screen.
class _AttachmentBubble extends StatelessWidget {
  const _AttachmentBubble({required this.attachment, required this.isMine, required this.otherUserId});
  final MessageAttachment attachment;
  final bool isMine;
  final String otherUserId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = isMine ? onColor(theme.colorScheme.secondary) : theme.colorScheme.onSurface;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMine ? 16 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 16),
    );

    if (attachment.isVoice) {
      return _VoiceMessageBubble(
        attachment: attachment,
        isMine: isMine,
        otherUserId: otherUserId,
        foreground: foreground,
        background: isMine ? theme.colorScheme.secondary : theme.cardColor,
        borderRadius: borderRadius,
      );
    }

    if (attachment.isImage) {
      return Material(
        color: isMine ? theme.colorScheme.secondary : theme.cardColor,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openFullScreen(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: 'chat_image_${attachment.id}',
                child: Image.network(
                  attachment.coverUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : Container(
                          height: 200,
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(),
                        ),
                  errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    color: theme.scaffoldBackgroundColor,
                    alignment: Alignment.center,
                    child: Icon(Icons.broken_image_outlined, color: theme.hintColor),
                  ),
                ),
              ),
              if (attachment.caption.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(attachment.caption, style: TextStyle(color: foreground)),
                ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: isMine ? theme.colorScheme.secondary : theme.cardColor,
      borderRadius: borderRadius,
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

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (context, animation, __) => FadeTransition(
        opacity: animation,
        child: _FullScreenImageViewer(
          heroTag: 'chat_image_${attachment.id}',
          imageUrl: attachment.coverUrl,
        ),
      ),
    ));
  }

  Widget _fallbackArt(ThemeData theme, {IconData icon = Icons.music_note}) => Container(
        width: 48,
        height: 48,
        color: theme.scaffoldBackgroundColor,
        child: Icon(icon, size: 20),
      );
}

/// A voice-message bubble: play/pause + a live position/duration label.
/// The recording is fetched and decrypted on first tap (see
/// [MessagesProvider.downloadDecryptedVoice]) into a local temp file,
/// then handed to a dedicated [AudioPlayer] instance — deliberately NOT
/// the app's shared music player (`PlayerProvider`), since playing a
/// voice note shouldn't interrupt or get mixed up with whatever track
/// the person is currently listening to.
class _VoiceMessageBubble extends StatefulWidget {
  const _VoiceMessageBubble({
    required this.attachment,
    required this.isMine,
    required this.otherUserId,
    required this.foreground,
    required this.background,
    required this.borderRadius,
  });

  final MessageAttachment attachment;
  final bool isMine;
  final String otherUserId;
  final Color foreground;
  final Color background;
  final BorderRadius borderRadius;

  @override
  State<_VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<_VoiceMessageBubble> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  bool _loading = false;
  bool _playing = false;
  bool _failed = false;
  Duration _position = Duration.zero;
  Duration? _totalDuration;

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_failed) {
      setState(() => _failed = false);
    }
    final player = _player;
    if (player != null) {
      if (_playing) {
        await player.pause();
      } else {
        if (player.position >= (player.duration ?? Duration.zero)) {
          await player.seek(Duration.zero);
        }
        await player.play();
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final bytes = await context
          .read<MessagesProvider>()
          .downloadDecryptedVoice(widget.attachment.audioUrl, otherUserId: widget.otherUserId);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/voice_msg_${widget.attachment.id}.m4a');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final newPlayer = AudioPlayer();
      _stateSub = newPlayer.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() {
          _playing = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _playing = false;
            newPlayer.seek(Duration.zero);
            newPlayer.pause();
          }
        });
      });
      _positionSub = newPlayer.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _totalDuration = await newPlayer.setFilePath(file.path);
      _player = newPlayer;
      await newPlayer.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('voice_message_playback_failed'))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalDuration ?? Duration(seconds: widget.attachment.durationSeconds);
    final progress = total.inMilliseconds == 0 ? 0.0 : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Material(
      color: widget.background,
      borderRadius: widget.borderRadius,
      child: InkWell(
        borderRadius: widget.borderRadius,
        onTap: _loading ? null : _toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: _loading
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2, color: widget.foreground),
                      )
                    : Icon(
                        _failed
                            ? Icons.error_outline
                            : (_playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                        size: 36,
                        color: widget.foreground,
                      ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: widget.foreground.withOpacity(0.25),
                        valueColor: AlwaysStoppedAnimation(widget.foreground),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.lock, size: 11, color: widget.foreground.withOpacity(0.75)),
                        const SizedBox(width: 3),
                        Text(
                          formatDuration(_player != null ? _position : total),
                          style: TextStyle(color: widget.foreground.withOpacity(0.85), fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen viewer opened by tapping an image attachment. Pinch/zoom
/// via [InteractiveViewer], tap the backdrop to dismiss, or tap the save
/// button to download the image to the device's actual Photos/Gallery
/// (not just the app's network-image cache) via the `gal` package.
class _FullScreenImageViewer extends StatefulWidget {
  const _FullScreenImageViewer({required this.heroTag, required this.imageUrl});
  final String heroTag;
  final String imageUrl;

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  bool _saving = false;

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final hasAccess = await Gal.hasAccess() || await Gal.requestAccess();
      if (!hasAccess) {
        if (mounted) _showSnack(context.tr('photos_permission_denied'));
        return;
      }
      final response = await http.get(Uri.parse(widget.imageUrl));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      await Gal.putImageBytes(response.bodyBytes, name: 'reynmusic_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) _showSnack(context.tr('image_saved'));
    } catch (_) {
      if (mounted) _showSnack(context.tr('image_save_failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: Hero(
                tag: widget.heroTag,
                child: InteractiveViewer(
                  child: Image.network(widget.imageUrl),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: GestureDetector(
                    // Swallow the tap so it doesn't fall through to the
                    // dismiss-on-tap GestureDetector behind it.
                    onTap: () {},
                    child: Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: context.tr('save_image'),
                        onPressed: _saving ? null : _saveToGallery,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.download_rounded, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
