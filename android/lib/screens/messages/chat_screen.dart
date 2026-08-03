import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import '../../models/message.dart';
import '../../models/message_attachment.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../providers/messages_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/message_notification_service.dart';
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
  static const _maxRecordingDuration = Duration(minutes: 10);
  bool _isRecording = false;
  bool _isUploadingVoice = false;
  bool _isUploadingVideoNote = false;
  DateTime? _recordingStartedAt;
  Timer? _recordTicker;
  Duration _recordingElapsed = Duration.zero;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    // While this thread is open, its messages already show up live in the
    // chat itself — suppress the system notification for it (see
    // MessageNotificationService).
    MessageNotificationService.instance.setOpenThread(widget.otherUserId);
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
    MessageNotificationService.instance.setOpenThread(null);
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

  void _showMessageOptions(DirectMessage message, {required bool editable}) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (editable)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(context.tr('edit_message')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _editMessage(message);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(context.tr('delete_message'), style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteMessage(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMessage(DirectMessage message) async {
    final controller = TextEditingController(text: message.text);
    final newText = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('edit_message')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: DirectMessage.maxLength,
          maxLines: 5,
          minLines: 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(context.tr('save')),
          ),
        ],
      ),
    );
    if (newText == null || newText.isEmpty || newText == message.text || !mounted) return;
    try {
      await context.read<MessagesProvider>().editMessage(
            otherUserId: widget.otherUserId,
            messageId: message.id,
            newText: newText,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteMessage(DirectMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('delete_message')),
        content: Text(context.tr('delete_message_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('delete_message'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<MessagesProvider>().deleteMessage(otherUserId: widget.otherUserId, messageId: message.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isUploadingVoice || _isUploadingVideoNote) return;
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
      final elapsed = DateTime.now().difference(_recordingStartedAt!);
      setState(() => _recordingElapsed = elapsed);
      if (elapsed >= _maxRecordingDuration) {
        // Hit the cap — finalize and send exactly like a manual stop,
        // rather than silently continuing to record past the limit.
        _recordTicker?.cancel();
        _stopAndSendRecording();
      }
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


  /// Opens the round-video-message recorder ("кружок"); on success
  /// encrypts and uploads it exactly like [_stopAndSendRecording] does
  /// for voice notes (same E2EE pipeline, see
  /// [MessagesProvider.uploadVideoNoteAttachment]), then sends it.
  Future<void> _openVideoNoteRecorder() async {
    if (_isRecording || _isUploadingVoice || _isUploadingVideoNote) return;
    final result = await Navigator.of(context).push<(String, int)>(
      MaterialPageRoute(builder: (_) => const _VideoNoteRecorderScreen(), fullscreenDialog: true),
    );
    if (result == null || !mounted) return;
    final (path, durationSeconds) = result;
    final myId = context.read<AuthProvider>().user?.id;
    if (myId == null) return;
    setState(() => _isUploadingVideoNote = true);
    try {
      final attachment = await context.read<MessagesProvider>().uploadVideoNoteAttachment(
            path,
            recipientId: widget.otherUserId,
            durationSeconds: durationSeconds,
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
      if (mounted) setState(() => _isUploadingVideoNote = false);
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
                                child: GestureDetector(
                                  onLongPress: isMine && !pending
                                      ? () => _showMessageOptions(message, editable: attachment == null)
                                      : null,
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
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          message.text,
                                          style: TextStyle(color: isMine ? onColor(accent) : theme.colorScheme.onSurface),
                                        ),
                                        if (message.editedAt != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              context.tr('message_edited_tag'),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontStyle: FontStyle.italic,
                                                color: (isMine ? onColor(accent) : theme.colorScheme.onSurface)
                                                    .withOpacity(0.6),
                                              ),
                                            ),
                                          ),
                                      ],
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
                  else if (_isUploadingVideoNote)
                    _UploadingVideoBar(theme: theme)
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
                            onTap: _openVideoNoteRecorder,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(Icons.videocam_outlined, size: 20, color: theme.hintColor),
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

/// Same as [_UploadingVoiceBar], shown while a just-recorded round video
/// message is being encrypted and uploaded (see
/// ChatScreen._openVideoNoteRecorder).
class _UploadingVideoBar extends StatelessWidget {
  const _UploadingVideoBar({required this.theme});
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
          Text(context.tr('sending_video_message'), style: TextStyle(color: theme.hintColor)),
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

    if (attachment.isVideoNote) {
      return _VideoNoteMessageBubble(attachment: attachment, otherUserId: otherUserId);
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
  static const _progressBarWidth = 130.0;

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

  Future<void> _seekToFraction(double fraction) async {
    final total = _totalDuration ?? Duration(seconds: widget.attachment.durationSeconds);
    if (total == Duration.zero) return;
    final target = total * fraction.clamp(0.0, 1.0);
    var player = _player;
    if (player == null) {
      // Not loaded yet — load (which also starts playback from zero),
      // then jump to the tapped position once the player is ready.
      await _toggle();
      player = _player;
    }
    await player?.seek(target);
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
                width: _progressBarWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => _seekToFraction(
                        details.localPosition.dx / _progressBarWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor: widget.foreground.withOpacity(0.25),
                            valueColor: AlwaysStoppedAnimation(widget.foreground),
                          ),
                        ),
                      ),
                    ),
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

/// A round video message ("кружок") bubble: circular video, tap to
/// decrypt-and-play. Same trust model/flow as [_VoiceMessageBubble] —
/// the recording is fetched and decrypted on first tap (see
/// [MessagesProvider.downloadDecryptedVideoNote]) into a local temp
/// file, then handed to a dedicated [VideoPlayerController].
class _VideoNoteMessageBubble extends StatefulWidget {
  const _VideoNoteMessageBubble({required this.attachment, required this.otherUserId});

  final MessageAttachment attachment;
  final String otherUserId;

  @override
  State<_VideoNoteMessageBubble> createState() => _VideoNoteMessageBubbleState();
}

class _VideoNoteMessageBubbleState extends State<_VideoNoteMessageBubble> {
  static const _size = 220.0;

  VideoPlayerController? _controller;
  bool _loading = false;
  bool _playing = false;
  bool _failed = false;
  Duration _position = Duration.zero;
  Duration? _totalDuration;

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  /// Mirrors the controller's playing/position state into this widget,
  /// and — since [VideoPlayerController] has no built-in "completed"
  /// event — detects end-of-clip itself and rewinds to the start
  /// (same behavior as [_VoiceMessageBubble]'s completion handling).
  void _onControllerUpdate() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    final duration = value.duration;
    if (duration > Duration.zero && value.position >= duration) {
      controller.pause();
      controller.seekTo(Duration.zero);
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
      return;
    }
    setState(() {
      _playing = value.isPlaying;
      _position = value.position;
    });
  }

  Future<void> _toggle() async {
    if (_failed) setState(() => _failed = false);
    final controller = _controller;
    if (controller != null) {
      if (_playing) {
        await controller.pause();
      } else {
        if (controller.value.position >= controller.value.duration) {
          await controller.seekTo(Duration.zero);
        }
        await controller.play();
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final bytes = await context
          .read<MessagesProvider>()
          .downloadDecryptedVideoNote(widget.attachment.audioUrl, otherUserId: widget.otherUserId);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/video_note_${widget.attachment.id}.mp4');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final newController = VideoPlayerController.file(file);
      await newController.initialize();
      await newController.setLooping(false);
      newController.addListener(_onControllerUpdate);
      _controller = newController;
      _totalDuration = newController.value.duration;
      await newController.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('video_message_playback_failed'))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Scrubs to [fraction] (0..1) of the clip — same tap/drag-to-seek
  /// pattern as [_VoiceMessageBubble._seekToFraction]. If nothing's
  /// been loaded yet, loads and starts playback first (that also lands
  /// on position zero), then jumps to the target.
  Future<void> _seekToFraction(double fraction) async {
    var controller = _controller;
    if (controller == null) {
      await _toggle();
      controller = _controller;
    }
    if (controller == null || !controller.value.isInitialized) return;
    final total = controller.value.duration;
    if (total == Duration.zero) return;
    final target = total * fraction.clamp(0.0, 1.0);
    await controller.seekTo(target);
    if (mounted) setState(() => _position = target);
  }

  /// Converts a touch point on the ring (relative to its own center)
  /// into a clockwise-from-12-o'clock fraction and seeks there —
  /// what makes the ring itself function as a scrub control.
  void _seekFromRingTouch(Offset localPosition, double ringSize) {
    final center = Offset(ringSize / 2, ringSize / 2);
    final vector = localPosition - center;
    if (vector.distance == 0) return;
    final angle = (math.atan2(vector.dx, -vector.dy) + 2 * math.pi) % (2 * math.pi);
    _seekToFraction(angle / (2 * math.pi));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller != null && controller.value.isInitialized;
    final total = _totalDuration ?? Duration(seconds: widget.attachment.durationSeconds);
    final progress =
        total.inMilliseconds == 0 ? 0.0 : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    const ringStroke = 4.0;
    const ringGap = 6.0;
    const outerSize = _size + (ringGap + ringStroke) * 2;

    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The ring itself — background track + white progress arc,
          // drawn just outside the video circle.
          IgnorePointer(
            child: CustomPaint(
              size: const Size(outerSize, outerSize),
              painter: _RingProgressPainter(progress: progress, strokeWidth: ringStroke),
            ),
          ),
          // Donut-shaped hit area (excludes the video circle in the
          // middle) — tap or drag anywhere on the ring to scrub.
          ClipPath(
            clipper: _DonutClipper(innerRadius: _size / 2, outerRadius: outerSize / 2),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _seekFromRingTouch(details.localPosition, outerSize),
              onPanStart: (details) => _seekFromRingTouch(details.localPosition, outerSize),
              onPanUpdate: (details) => _seekFromRingTouch(details.localPosition, outerSize),
              child: const SizedBox(width: outerSize, height: outerSize),
            ),
          ),
          // The video circle — tap to play/pause. Clipped to a circle
          // (not just visually but for hit-testing too) so it doesn't
          // steal touches from the ring in its bounding box's corners.
          ClipOval(
            child: GestureDetector(
              onTap: _loading ? null : _toggle,
              child: SizedBox(
                width: _size,
                height: _size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: _size,
                      height: _size,
                      color: Colors.black,
                      child: initialized
                          ? FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: controller.value.size.width,
                                height: controller.value.size.height,
                                child: VideoPlayer(controller),
                              ),
                            )
                          : null,
                    ),
                    if (_loading)
                      const CircularProgressIndicator(color: Colors.white)
                    else if (_failed)
                      const Icon(Icons.error_outline, color: Colors.white, size: 40)
                    else if (!_playing)
                      Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                      ),
                    Positioned(
                      bottom: 12,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock, size: 11, color: Colors.white70),
                          const SizedBox(width: 3),
                          Text(
                            formatDuration(controller != null ? _position : total),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the scrub ring around a [_VideoNoteMessageBubble]: a dim
/// full-circle track plus a solid white arc for [progress] (0..1),
/// swept clockwise starting at 12 o'clock.
class _RingProgressPainter extends CustomPainter {
  const _RingProgressPainter({required this.progress, required this.strokeWidth});
  final double progress;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingProgressPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.strokeWidth != strokeWidth;
}

/// Clips hit-testing (and, if ever painted directly, rendering) to a
/// donut between [innerRadius] and [outerRadius] — used so the ring's
/// [GestureDetector] only responds to touches on the ring itself, not
/// the video circle sitting inside it.
class _DonutClipper extends CustomClipper<Path> {
  const _DonutClipper({required this.innerRadius, required this.outerRadius});
  final double innerRadius;
  final double outerRadius;

  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    return Path()
      ..addOval(Rect.fromCircle(center: center, radius: outerRadius))
      ..addOval(Rect.fromCircle(center: center, radius: innerRadius))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(covariant _DonutClipper oldClipper) =>
      oldClipper.innerRadius != innerRadius || oldClipper.outerRadius != outerRadius;
}

/// Full-screen recorder for round video messages ("кружки"), pushed by
/// ChatScreen._openVideoNoteRecorder. Records a short front-camera clip
/// (capped at [_maxDuration]) and pops back with `(localFilePath,
/// durationSeconds)` on success, or `null` if cancelled. The clip is
/// still plaintext on disk at this point — encryption happens right
/// before upload, in YandexStorageApiService.uploadChatVideoNote (same
/// as voice notes).
class _VideoNoteRecorderScreen extends StatefulWidget {
  const _VideoNoteRecorderScreen();

  @override
  State<_VideoNoteRecorderScreen> createState() => _VideoNoteRecorderScreenState();
}

class _VideoNoteRecorderScreenState extends State<_VideoNoteRecorderScreen> {
  static const _maxDuration = Duration(seconds: 60);
  static const _previewSize = 260.0;

  CameraController? _controller;
  bool _initializing = true;
  bool _unavailable = false;
  bool _recording = false;
  DateTime? _startedAt;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: true);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (_) {
      if (mounted) setState(() { _initializing = false; _unavailable = true; });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null) return;
    if (_recording) {
      await _stopAndReturn();
      return;
    }
    try {
      await controller.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _startedAt = DateTime.now();
        _elapsed = Duration.zero;
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        final elapsed = DateTime.now().difference(_startedAt!);
        setState(() => _elapsed = elapsed);
        if (elapsed >= _maxDuration) _stopAndReturn();
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tr('camera_permission_denied'))));
      }
    }
  }

  Future<void> _stopAndReturn() async {
    _ticker?.cancel();
    final controller = _controller;
    if (controller == null || !controller.value.isRecordingVideo) return;
    try {
      final file = await controller.stopVideoRecording();
      final elapsed = _elapsed;
      if (mounted) setState(() => _recording = false);
      if (elapsed.inSeconds < 1) {
        // Too short to be a real message — discard, same rule as voice.
        try {
          await File(file.path).delete();
        } catch (_) {}
        return;
      }
      if (mounted) Navigator.of(context).pop((file.path, elapsed.inSeconds));
    } catch (_) {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    final controller = _controller;
    if (controller != null && controller.value.isRecordingVideo) {
      try {
        final file = await controller.stopVideoRecording();
        try {
          await File(file.path).delete();
        } catch (_) {}
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            if (_initializing)
              const CircularProgressIndicator(color: Colors.white)
            else if (controller == null || _unavailable)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.tr('camera_permission_denied'),
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ClipOval(
                child: SizedBox(
                  width: _previewSize,
                  height: _previewSize,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: controller.value.previewSize?.height ?? _previewSize,
                      height: controller.value.previewSize?.width ?? _previewSize,
                      child: CameraPreview(controller),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (_recording)
              Text(
                formatDuration(_elapsed),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    onPressed: _cancel,
                    icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  ),
                  GestureDetector(
                    onTap: controller == null ? null : _toggleRecording,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          shape: _recording ? BoxShape.rectangle : BoxShape.circle,
                          borderRadius: _recording ? BorderRadius.circular(6) : null,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('hold_to_record_video'),
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
            ),
            const SizedBox(height: 12),
          ],
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
