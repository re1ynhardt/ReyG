import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  String? _audioPath;
  String? _audioName;
  String? _coverPath;
  String? _coverName;
  bool _uploading = false;

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
      await context.read<LibraryProvider>().uploadTrack(
            title: _title.text.trim(),
            artist: _artist.text.trim(),
            album: _album.text.trim(),
            localAudioPath: _audioPath!,
            localCoverPath: _coverPath,
          );
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
