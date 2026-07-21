import 'dart:ui';

import 'package:flutter/material.dart';
import '../models/track.dart';
import '../providers/app_state.dart';
import 'artist_avatar.dart';
import 'track_list_tile.dart';

/// Premium, glassy card shown for an artist that matches the Search
/// query: a single frosted, semi-transparent "window" holding the avatar
/// + name header, two pill actions ("Listen" / "Open"), and up to 3 of
/// the artist's tracks previewed underneath — the whole thing reads as
/// one floating glass panel rather than a card with a plain list below it.
class ArtistResultCard extends StatelessWidget {
  const ArtistResultCard({
    super.key,
    required this.artist,
    required this.avatarUrl,
    required this.trackCount,
    required this.previewTracks,
    required this.playingTrackId,
    required this.onListen,
    required this.onOpen,
    required this.onTrackTap,
    required this.onTrackMore,
  });

  final String artist;
  final String avatarUrl;
  final int trackCount;
  /// Up to 3 of the artist's tracks (newest-first), shown under the header.
  final List<Track> previewTracks;
  final String? playingTrackId;
  final VoidCallback onListen;
  final VoidCallback onOpen;
  final void Function(int previewIndex) onTrackTap;
  final void Function(Track track) onTrackMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.secondary;
    final hint = theme.hintColor;
    final divider = theme.dividerColor.withOpacity(0.5);
    final canListen = previewTracks.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
      child: _GlassPanel(
        isDark: isDark,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 14, 14, previewTracks.isEmpty ? 14 : 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onOpen,
                  child: Row(
                    children: [
                      ArtistAvatar(imageUrl: avatarUrl, radius: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$trackCount ${context.tr('all_tracks').toLowerCase()}',
                              style: TextStyle(color: hint, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, color: hint, size: 22),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _PillButton(
                      label: context.tr('listen'),
                      icon: Icons.play_arrow_rounded,
                      filled: true,
                      color: accent,
                      enabled: canListen,
                      onTap: onListen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PillButton(
                      label: context.tr('open'),
                      icon: Icons.arrow_forward_rounded,
                      filled: false,
                      color: theme.colorScheme.primary,
                      enabled: true,
                      onTap: onOpen,
                    ),
                  ),
                ],
              ),
              if (previewTracks.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(height: 1, thickness: 1, color: divider),
                const SizedBox(height: 2),
                for (var i = 0; i < previewTracks.length; i++)
                  TrackListTile(
                    track: previewTracks[i],
                    dense: true,
                    isPlaying: playingTrackId == previewTracks[i].id,
                    onTap: () => onTrackTap(i),
                    trailing: IconButton(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onPressed: () => onTrackMore(previewTracks[i]),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Frosted "glass" container: blurred + translucent fill, a hairline
/// light-catching border, and a soft top highlight so it reads as a
/// premium floating window rather than a flat tinted box, regardless of
/// which of the app's themes is active.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.isDark, required this.child});

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    final borderColor = isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.08);
    final fillTop = isDark ? Colors.white.withOpacity(0.10) : Colors.white.withOpacity(0.55);
    final fillBottom = isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.28);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: borderColor, width: 1),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [fillTop, fillBottom],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.28 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Pill-shaped action button used for "Listen" / "Open", styled after the
/// Shuffle/Mix buttons on the reference artist page — filled for the
/// primary action, translucent-outlined for the secondary one.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color.withOpacity(enabled ? 1 : 0.4);
    final bg = filled
        ? color.withOpacity(enabled ? 1 : 0.35)
        : color.withOpacity(0.10);
    final border = filled ? null : Border.all(color: color.withOpacity(enabled ? 0.35 : 0.15), width: 1);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: enabled ? onTap : null,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(24),
            border: border,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
