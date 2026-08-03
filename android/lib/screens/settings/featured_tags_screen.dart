import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';

/// Developer-only. Lets a developer account type up to 4 hashtags into 4
/// fixed slots; saving overwrites [LibraryProvider.featuredTags] for
/// *every* account — this is the single global set of tags shown in the
/// "Featured tags" block on everyone's Home screen, not a personal pick.
class FeaturedTagsScreen extends StatefulWidget {
  const FeaturedTagsScreen({super.key});

  @override
  State<FeaturedTagsScreen> createState() => _FeaturedTagsScreenState();
}

class _FeaturedTagsScreenState extends State<FeaturedTagsScreen> {
  late final List<TextEditingController> _controllers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current = context.read<LibraryProvider>().featuredTags;
    _controllers = List.generate(
      4,
      (i) => TextEditingController(text: i < current.length ? current[i] : ''),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  String _tr(String key) => AppStrings.t(context.read<AppState>().locale, key);

  Future<void> _save() async {
    // Trim/lowercase before validating so "  Chill " and "chill" are
    // treated the same way the hashtag-on-a-track flow already does.
    final tags = _controllers.map((c) => c.text.trim().toLowerCase()).toList();
    for (final tag in tags) {
      if (tag.isEmpty) continue;
      if (tag.length > Track.maxHashtagLength) {
        _showError('${_tr('hashtag_english_only')} (max ${Track.maxHashtagLength})');
        return;
      }
      if (!Track.isValidHashtag(tag)) {
        _showError(_tr('hashtag_english_only'));
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await context.read<LibraryProvider>().setFeaturedTags(tags);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('featured_tags_saved'))));
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('select_tags'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.tr('select_tags_description'),
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < 4; i++) ...[
            TextField(
              controller: _controllers[i],
              enabled: !_saving,
              maxLength: Track.maxHashtagLength,
              decoration: InputDecoration(
                labelText: '${context.tr('tag')} ${i + 1}',
                hintText: context.tr('hashtag_hint'),
                prefixText: '#',
                counterText: '',
              ),
              onChanged: (v) {
                final lower = v.toLowerCase();
                if (lower != v) {
                  _controllers[i].value = TextEditingValue(
                    text: lower,
                    selection: TextSelection.collapsed(offset: lower.length),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(context.tr('save')),
          ),
        ],
      ),
    );
  }
}
