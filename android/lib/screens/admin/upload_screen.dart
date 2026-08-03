import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/library_provider.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _album = TextEditingController();
  final _hashtagInput = TextEditingController();
  String? _audioPath;
  String? _audioName;
  String? _coverPath;
  String? _coverName;
  bool _uploading = false;
  bool _hashtagInvalidHint = false;
  // Optional, up to Track.maxHashtags — sent (one addHashtag call per tag)
  // right after the track itself finishes uploading.
  final List<String> _hashtags = [];

  void _addHashtag() {
    final tag = _hashtagInput.text.trim().toLowerCase();
    if (tag.isEmpty) return;
    if (_hashtags.length >= Track.maxHashtags || _hashtags.contains(tag) || !Track.isValidHashtag(tag)) {
      _hashtagInput.clear();
      return;
    }
    setState(() {
      _hashtags.add(tag);
      _hashtagInput.clear();
    });
  }

  void _removeHashtag(String tag) => setState(() => _hashtags.remove(tag));

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _audioPath = result.files.single.path;
        _audioName = result.files.single.name;
      });
    }
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _coverPath = result.files.single.path;
        _coverName = result.files.single.name;
      });
    }
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _artist.text.trim().isEmpty || _audioPath == null) return;
    setState(() => _uploading = true);
    try {
      final library = context.read<LibraryProvider>();
      final track = await library.uploadTrack(
        title: _title.text.trim(),
        artist: _artist.text.trim(),
        album: _album.text.trim(),
        localAudioPath: _audioPath!,
        localCoverPath: _coverPath,
      );
      // Hashtags aren't part of the upload call itself — the track needs
      // to exist first — so add each one (if any) right after, the same
      // way the now-playing screen's "add hashtag" dialog does.
      for (final tag in _hashtags) {
        await library.addHashtag(trackId: track.id, hashtag: tag);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('upload_success'))));
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _hashtagInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isSupport = auth.isSupport;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('upload_track'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isSupport ? context.tr('support_account') : context.tr('performer_account'),
                      style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(controller: _title, decoration: InputDecoration(labelText: context.tr('title'))),
            const SizedBox(height: 12),
            TextField(controller: _artist, decoration: InputDecoration(labelText: context.tr('artist'))),
            const SizedBox(height: 12),
            TextField(controller: _album, decoration: InputDecoration(labelText: context.tr('album'))),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _pickAudio,
              icon: const Icon(Icons.audiotrack),
              label: Text(_audioName ?? context.tr('choose_audio_file')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickCover,
              icon: const Icon(Icons.image),
              label: Text(_coverName ?? context.tr('choose_cover_image')),
            ),
            const SizedBox(height: 20),
            Text(context.tr('upload_hashtags_label'), style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _hashtagInput,
              enabled: _hashtags.length < Track.maxHashtags,
              maxLength: Track.maxHashtagLength,
              inputFormatters: [
                _UploadHashtagInputFormatter(
                  onValidityChanged: (hadInvalidChars) {
                    if (hadInvalidChars != _hashtagInvalidHint) {
                      setState(() => _hashtagInvalidHint = hadInvalidChars);
                    }
                  },
                ),
              ],
              decoration: InputDecoration(
                prefixText: '#',
                hintText: context.tr('hashtag_hint'),
                errorText: _hashtagInvalidHint ? context.tr('hashtag_english_only') : null,
                helperText: _hashtags.length >= Track.maxHashtags ? context.tr('hashtag_limit_reached') : null,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _hashtags.length < Track.maxHashtags ? _addHashtag : null,
                ),
              ),
              onSubmitted: (_) => _addHashtag(),
            ),
            if (_hashtags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _hashtags
                    .map((tag) => Chip(
                          label: Text('#$tag'),
                          onDeleted: () => _removeHashtag(tag),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _uploading ? null : _submit,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _uploading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('upload')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same character rule as [Track.hashtagPattern] (lowercase English
/// letters/digits only): lowercases as the person types, strips anything
/// else, and reports via [onValidityChanged] whether a character had to
/// be stripped so the field can show a live hint. Mirrors the private
/// formatter used by the "add hashtag" dialog on the now-playing screen.
class _UploadHashtagInputFormatter extends TextInputFormatter {
  _UploadHashtagInputFormatter({required this.onValidityChanged});

  final ValueChanged<bool> onValidityChanged;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final lowered = newValue.text.toLowerCase();
    final filtered = lowered.replaceAll(RegExp(r'[^a-z0-9]'), '');
    onValidityChanged(filtered.length < newValue.text.length);
    if (filtered == newValue.text) return newValue;
    return TextEditingValue(text: filtered, selection: TextSelection.collapsed(offset: filtered.length));
  }
}
