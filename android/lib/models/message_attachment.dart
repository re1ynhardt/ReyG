import 'dart:convert';

import 'track.dart';

/// A track or playlist share embedded inside a [DirectMessage].
///
/// There is deliberately no new backend collection and no change to
/// [ApiService]/`sendMessage` for this: the attachment is just encoded as
/// a JSON string and sent as the message's `text`, prefixed with
/// [MessageAttachment.marker]. That means it automatically gets
/// end-to-end encrypted/decrypted for free by the existing Messages
/// pipeline (`YandexStorageApiService`'s E2EE section treats it as
/// opaque text) — no other `ApiService` method needed to change.
///
/// Track attachments carry a full denormalized snapshot of the track
/// (title/artist/cover/audio URL/duration) so they still render and play
/// correctly even if the track is later removed from the catalog.
/// Playlist attachments stay small and carry only the track ids — the
/// receiving side resolves those against the shared, global track
/// catalog (which every account already has loaded) when the attachment
/// is opened.
class MessageAttachment {
  const MessageAttachment.track({
    required this.id,
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.audioUrl,
    required this.durationSeconds,
    this.caption = '',
  })  : type = _typeTrack,
        playlistName = '',
        trackIds = const [];

  const MessageAttachment.playlist({
    required this.id,
    required this.playlistName,
    required this.coverUrl,
    required this.trackIds,
    this.caption = '',
  })  : type = _typePlaylist,
        title = '',
        artist = '',
        audioUrl = '',
        durationSeconds = 0;

  /// A photo shared in a chat thread. [coverUrl] is the uploaded image
  /// itself (see `YandexStorageApiService.uploadChatImage`) — reusing the
  /// shared `coverUrl` field rather than adding a new one, since it's
  /// already exactly "the image to display" for every other attachment
  /// type.
  const MessageAttachment.image({
    required this.id,
    required this.coverUrl,
    this.caption = '',
  })  : type = _typeImage,
        title = '',
        artist = '',
        audioUrl = '',
        durationSeconds = 0,
        playlistName = '',
        trackIds = const [];

  /// A voice message recorded in a chat thread. [audioUrl] points at the
  /// ENCRYPTED recording (see `YandexStorageApiService.uploadChatVoice`)
  /// — unlike [MessageAttachment.image], the bytes at that URL are
  /// opaque AES-256-GCM ciphertext, not a playable file, so playback
  /// always goes through `YandexStorageApiService.downloadChatVoice` to
  /// decrypt them first. [durationSeconds] is only ever a display hint
  /// (waveform/label) computed client-side at recording time.
  const MessageAttachment.voice({
    required this.id,
    required this.audioUrl,
    required this.durationSeconds,
    this.caption = '',
  })  : type = _typeVoice,
        title = '',
        artist = '',
        coverUrl = '',
        playlistName = '',
        trackIds = const [];

  /// A round video message ("кружок") recorded in a chat thread.
  /// [audioUrl] points at the ENCRYPTED recording (see
  /// `YandexStorageApiService.uploadChatVideoNote`) — exactly the same
  /// scheme as [MessageAttachment.voice], just carrying video bytes
  /// instead of audio: opaque AES-256-GCM ciphertext at rest and in
  /// transit, decrypted client-side via
  /// `YandexStorageApiService.downloadChatVideoNote` before playback.
  /// Reuses the shared [audioUrl] field (like [image] reuses
  /// [coverUrl]) rather than adding a video-only field, since it's
  /// already exactly "the encrypted blob URL" every other type needs.
  const MessageAttachment.videoNote({
    required this.id,
    required this.audioUrl,
    required this.durationSeconds,
    this.caption = '',
  })  : type = _typeVideoNote,
        title = '',
        artist = '',
        coverUrl = '',
        playlistName = '',
        trackIds = const [];

  static const _typeTrack = 'track';
  static const _typePlaylist = 'playlist';
  static const _typeImage = 'image';
  static const _typeVoice = 'voice';
  static const _typeVideoNote = 'video_note';

  /// Leading marker that flags a [DirectMessage.text] as carrying an
  /// attachment payload rather than plain user-typed text. Uses a
  /// control character no normal keyboard can type, so it can never
  /// collide with a real message.
  static const marker = '\u0001ATTACH\u0001';

  final String type;
  final String id;

  // Track fields.
  final String title;
  final String artist;
  final String audioUrl;
  final int durationSeconds;

  // Playlist fields.
  final String playlistName;
  final List<String> trackIds;

  // Shared.
  final String coverUrl;
  /// Optional text typed alongside the attachment in the composer, sent
  /// together with it in the same message (like a caption). Empty when
  /// the attachment was sent with no accompanying text.
  final String caption;

  bool get isTrack => type == _typeTrack;
  bool get isPlaylist => type == _typePlaylist;
  bool get isImage => type == _typeImage;
  bool get isVoice => type == _typeVoice;
  bool get isVideoNote => type == _typeVideoNote;

  /// Returns a copy of this attachment with [caption] replaced — used by
  /// the composer to fold in whatever text was typed at send time.
  MessageAttachment withCaption(String caption) {
    if (isTrack) {
      return MessageAttachment.track(
        id: id,
        title: title,
        artist: artist,
        coverUrl: coverUrl,
        audioUrl: audioUrl,
        durationSeconds: durationSeconds,
        caption: caption,
      );
    }
    if (isImage) {
      return MessageAttachment.image(id: id, coverUrl: coverUrl, caption: caption);
    }
    if (isVoice) {
      return MessageAttachment.voice(
        id: id,
        audioUrl: audioUrl,
        durationSeconds: durationSeconds,
        caption: caption,
      );
    }
    if (isVideoNote) {
      return MessageAttachment.videoNote(
        id: id,
        audioUrl: audioUrl,
        durationSeconds: durationSeconds,
        caption: caption,
      );
    }
    return MessageAttachment.playlist(
      id: id,
      playlistName: playlistName,
      coverUrl: coverUrl,
      trackIds: trackIds,
      caption: caption,
    );
  }

  /// The [Track] to hand to `PlayerProvider` for a track attachment.
  /// Only meaningful when [isTrack].
  Track toTrack() => Track(
        id: id,
        title: title,
        artist: artist,
        album: '',
        coverUrl: coverUrl,
        audioUrl: audioUrl,
        duration: Duration(seconds: durationSeconds),
      );

  /// Encodes this attachment as a [DirectMessage.text] payload.
  String encode() {
    final Map<String, dynamic> json = isTrack
        ? {
            'type': type,
            'id': id,
            'title': title,
            'artist': artist,
            'cover_url': coverUrl,
            'audio_url': audioUrl,
            'duration_seconds': durationSeconds,
            'caption': caption,
          }
        : isImage
            ? {
                'type': type,
                'id': id,
                'cover_url': coverUrl,
                'caption': caption,
              }
            : isVoice
                ? {
                    'type': type,
                    'id': id,
                    'audio_url': audioUrl,
                    'duration_seconds': durationSeconds,
                    'caption': caption,
                  }
                : isVideoNote
                    ? {
                        'type': type,
                        'id': id,
                        'video_url': audioUrl,
                        'duration_seconds': durationSeconds,
                        'caption': caption,
                      }
                    : {
                        'type': type,
                        'id': id,
                        'name': playlistName,
                        'cover_url': coverUrl,
                        'track_ids': trackIds,
                        'caption': caption,
                      };
    return '$marker${jsonEncode(json)}';
  }

  /// Parses [text] as an attachment payload, or returns null if it's a
  /// plain user-typed message.
  static MessageAttachment? tryParse(String text) {
    if (!text.startsWith(marker)) return null;
    try {
      final json = jsonDecode(text.substring(marker.length)) as Map<String, dynamic>;
      switch (json['type']) {
        case _typeTrack:
          return MessageAttachment.track(
            id: json['id'] as String,
            title: json['title'] as String? ?? '',
            artist: json['artist'] as String? ?? '',
            coverUrl: json['cover_url'] as String? ?? '',
            audioUrl: json['audio_url'] as String? ?? '',
            durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
            caption: json['caption'] as String? ?? '',
          );
        case _typePlaylist:
          return MessageAttachment.playlist(
            id: json['id'] as String,
            playlistName: json['name'] as String? ?? '',
            coverUrl: json['cover_url'] as String? ?? '',
            trackIds: (json['track_ids'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
            caption: json['caption'] as String? ?? '',
          );
        case _typeImage:
          return MessageAttachment.image(
            id: json['id'] as String,
            coverUrl: json['cover_url'] as String? ?? '',
            caption: json['caption'] as String? ?? '',
          );
        case _typeVoice:
          return MessageAttachment.voice(
            id: json['id'] as String,
            audioUrl: json['audio_url'] as String? ?? '',
            durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
            caption: json['caption'] as String? ?? '',
          );
        case _typeVideoNote:
          return MessageAttachment.videoNote(
            id: json['id'] as String,
            audioUrl: json['video_url'] as String? ?? '',
            durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
            caption: json['caption'] as String? ?? '',
          );
      }
    } catch (_) {
      // Malformed payload (shouldn't happen from our own sender, but a
      // raw API call could send garbage after the marker) — fall back
      // to treating it as unparseable rather than crashing the chat.
    }
    return null;
  }
}
