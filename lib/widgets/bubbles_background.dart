import 'dart:math';

import 'package:flutter/material.dart';

/// Wraps [child] with a slow, looping field of translucent floating
/// bubbles. Used only when [AppThemeOption.bubbles] is active — see
/// `HarmonyApp`'s `MaterialApp.builder` in app.dart.
class BubblesBackground extends StatefulWidget {
  const BubblesBackground({super.key, required this.child});

  final Widget child;

  @override
  State<BubblesBackground> createState() => _BubblesBackgroundState();
}

class _BubblesBackgroundState extends State<BubblesBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Bubble> _bubbles;

  @override
  void initState() {
    super.initState();
    final rnd = Random(7);
    _bubbles = List.generate(16, (i) {
      return _Bubble(
        dx: rnd.nextDouble(),
        size: 10 + rnd.nextDouble() * 34,
        speed: 0.35 + rnd.nextDouble() * 0.65,
        phase: rnd.nextDouble(),
        opacity: 0.06 + rnd.nextDouble() * 0.10,
      );
    });
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _BubblesPainter(bubbles: _bubbles, t: _controller.value, color: accent),
                );
              },
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _Bubble {
  _Bubble({
    required this.dx,
    required this.size,
    required this.speed,
    required this.phase,
    required this.opacity,
  });

  final double dx; // horizontal position, 0..1 of width
  final double size;
  final double speed; // loops per animation cycle
  final double phase; // vertical offset within the loop, 0..1
  final double opacity;
}

class _BubblesPainter extends CustomPainter {
  _BubblesPainter({required this.bubbles, required this.t, required this.color});

  final List<_Bubble> bubbles;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bubbles) {
      // Rises from bottom to top, wrapping around, at its own speed/phase.
      final progress = (t * b.speed + b.phase) % 1.0;
      final y = size.height * (1 - progress);
      final x = size.width * b.dx + sin(progress * 2 * pi) * 14;
      final paint = Paint()
        ..color = color.withOpacity(b.opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), b.size / 2, paint);
      canvas.drawCircle(
        Offset(x, y),
        b.size / 2,
        Paint()
          ..color = color.withOpacity(b.opacity * 1.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BubblesPainter oldDelegate) => oldDelegate.t != t;
}
