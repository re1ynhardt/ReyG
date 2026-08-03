import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/post.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/posts_provider.dart';
import '../../widgets/cached_cover_image.dart';
import '../../widgets/track_list_tile.dart';

/// Composer for a new post: text (up to [Post.maxTextLength] chars),
/// up to [Post.maxImages] photos, one track already in the app's catalog
/// (this is an audio player — posting music links an existing [Track],
/// it never uploads new audio), and up to [Post.maxHashtags] hashtags.
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const _allowedImageExtensions = [
    'jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic', 'heif', 'tif', 'tiff',
  ];

  final _textController = TextEditingController();
  final _hashtagController = TextEditingController();
  final List<String> _imagePaths = [];
  final List<String> _hashtags = [];
  final List<Track> _tracks = [];
  bool _publishing = false;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    _hashtagController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining = Post.maxImages - _imagePaths.length;
    if (remaining <= 0) {
      setState(() => _error = context.trOnce('max_images_reached'));
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedImageExtensions,
      allowMultiple: true,
    );
    if (result == null) return;
    setState(() {
      for (final f in result.files.take(remaining)) {
        if (f.path != null) _imagePaths.add(f.path!);
      }
    });
  }

  Future<void> _pickTrack() async {
    if (_tracks.length >= Post.maxTracks) {
      setState(() => _error = context.trOnce('max_tracks_reached'));
      return;
    }
    final library = context.read<LibraryProvider>();
    final alreadyAdded = _tracks.map((t) => t.id).toSet();
    final available = library.tracks.where((t) => !alreadyAdded.contains(t.id)).toList();
    final track = await showModalBottomSheet<Track>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TrackPickerSheet(tracks: available),
    );
    if (track != null) {
      setState(() {
        _tracks.add(track);
        _error = null;
      });
    }
  }

  void _addHashtag() {
    final tag = _hashtagController.text.trim().toLowerCase();
    if (tag.isEmpty) return;
    if (tag.length > Post.maxHashtagLength) {
      setState(() => _error = context.trOnce('hashtag_too_long'));
      return;
    }
    if (!Post.isValidHashtag(tag)) {
      setState(() => _error = context.trOnce('hashtag_invalid'));
      return;
    }
    if (_hashtags.length >= Post.maxHashtags) {
      setState(() => _error = context.trOnce('max_hashtags_reached'));
      return;
    }
    if (_hashtags.contains(tag)) {
      _hashtagController.clear();
      return;
    }
    setState(() {
      _hashtags.add(tag);
      _hashtagController.clear();
      _error = null;
    });
  }

  Future<void> _publish() async {
    final text = _textController.text.trim();
    if (text.length > Post.maxTextLength) {
      setState(() => _error = context.trOnce('post_too_long'));
      return;
    }
    if (text.isEmpty && _imagePaths.isEmpty && _tracks.isEmpty) {
      setState(() => _error = context.trOnce('post_needs_content'));
      return;
    }
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      await context.read<PostsProvider>().createPost(
            text: text,
            localImagePaths: _imagePaths,
            trackIds: _tracks.map((t) => t.id).toList(),
            hashtags: _hashtags,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _publishing = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = Post.maxTextLength - _textController.text.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('create_post')),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: _publishing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(onPressed: _publish, child: Text(context.tr('post_publish'))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _textController,
            maxLines: 8,
            minLines: 3,
            maxLength: Post.maxTextLength,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: context.tr('post_text_hint'),
              border: const OutlineInputBorder(),
              counterText: '$remaining',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 12),
          if (_imagePaths.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final path in _imagePaths)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(path), width: 84, height: 84, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: IconButton(
                          icon: const Icon(Icons.cancel, size: 20),
                          tooltip: context.tr('remove_image'),
                          onPressed: () => setState(() => _imagePaths.remove(path)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(context.tr('post_add_image')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_tracks.isNotEmpty)
            for (final t in _tracks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(10),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedCoverImage(track: t, width: 44, height: 44),
                    ),
                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: context.tr('post_remove_track'),
                      onPressed: () => setState(() => _tracks.remove(t)),
                    ),
                  ),
                ),
              ),
          if (_tracks.length < Post.maxTracks)
            OutlinedButton.icon(
              onPressed: _pickTrack,
              icon: const Icon(Icons.music_note_outlined),
              label: Text(context.tr('post_add_track')),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in _hashtags)
                Chip(
                  label: Text('#$tag'),
                  onDeleted: () => setState(() => _hashtags.remove(tag)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hashtagController,
                  onSubmitted: (_) => _addHashtag(),
                  decoration: InputDecoration(
                    hintText: context.tr('post_hashtag_hint'),
                    prefixText: '#',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.add), onPressed: _addHashtag),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackPickerSheet extends StatefulWidget {
  const _TrackPickerSheet({required this.tracks});
  final List<Track> tracks;

  @override
  State<_TrackPickerSheet> createState() => _TrackPickerSheetState();
}

class _TrackPickerSheetState extends State<_TrackPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final term = _query.trim().toLowerCase();
    final filtered = term.isEmpty
        ? widget.tracks
        : widget.tracks.where((t) => t.title.toLowerCase().contains(term) || t.artist.toLowerCase().contains(term)).toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: context.tr('select_track_for_post'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final track = filtered[i];
                  return TrackListTile(track: track, onTap: () => Navigator.pop(context, track));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
