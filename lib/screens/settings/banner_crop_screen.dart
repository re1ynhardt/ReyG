import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../providers/app_state.dart';

/// Lets the user pan and pinch-zoom a picked image inside a fixed-aspect
/// frame to choose exactly how their profile banner will be cropped, then
/// rasterizes the visible frame to a new local PNG and returns its path
/// via [Navigator.pop]. Pops with `null` if the user backs out without
/// confirming.
///
/// Self-contained on purpose (no image-cropping package): the whole crop
/// is just a transformed image inside a [RepaintBoundary] that gets
/// snapshotted to bytes, so it doesn't touch `pubspec.yaml` or anything
/// backend-related.
class BannerCropScreen extends StatefulWidget {
  const BannerCropScreen({super.key, required this.imagePath});

  final String imagePath;

  /// Matches how the banner is displayed on the profile screen (see
  /// `_ProfileHero` in `user_profile_screen.dart`, which wraps its whole
  /// header in an `AspectRatio` using this same constant), so what the
  /// user frames here is exactly what other people will see. The header
  /// is now a tall portrait hero (photo behind the centered avatar/name/
  /// stats) rather than the old thin 3:1 strip above them, hence < 1.
  static const double aspectRatio = 0.85;

  @override
  State<BannerCropScreen> createState() => _BannerCropScreenState();
}

class _BannerCropScreenState extends State<BannerCropScreen> {
  static const double _maxUserZoom = 4;
  static const double _outputWidth = 1200;

  final _boundaryKey = GlobalKey();

  ui.Image? _image;
  bool _saving = false;
  bool _initialized = false;

  // 0..3, number of 90° clockwise turns applied to the image.
  int _quarterTurns = 0;

  // Scale to make the image cover the frame at zoom == 1, and the current
  // top-left offset of the (scaled) image relative to the frame, both in
  // frame-local logical pixels.
  double _baseScale = 1;
  double _zoom = 1;
  Offset _offset = Offset.zero;

  double _gestureStartZoom = 1;
  Offset _gestureStartOffset = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _image = frame.image);
  }

  Size _frameSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Size(width, width / BannerCropScreen.aspectRatio);
  }

  /// Bounding size of the (decoded, unscaled) image after applying
  /// [_quarterTurns] — width/height swap on a 90°/270° rotation.
  Size _rotatedImageSize() {
    final image = _image!;
    return _quarterTurns.isOdd
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());
  }

  /// Centers the image in the frame at the smallest zoom that still fully
  /// covers it (same idea as `BoxFit.cover`). Called the first time the
  /// frame size and decoded image are both known, and again after every
  /// rotation (simplest way to guarantee the frame is never left showing
  /// empty space post-rotation).
  void _centerImage(Size frame) {
    final rotated = _rotatedImageSize();
    _baseScale = math.max(frame.width / rotated.width, frame.height / rotated.height);
    _zoom = 1;
    final displayed = Size(rotated.width * _baseScale, rotated.height * _baseScale);
    _offset = Offset((frame.width - displayed.width) / 2, (frame.height - displayed.height) / 2);
  }

  void _rotate(Size frame) {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      _centerImage(frame);
    });
  }

  Offset _clampOffset(Offset raw, Size frame, Size displayed) {
    final minX = math.min(frame.width - displayed.width, 0.0);
    final minY = math.min(frame.height - displayed.height, 0.0);
    return Offset(raw.dx.clamp(minX, 0.0).toDouble(), raw.dy.clamp(minY, 0.0).toDouble());
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartZoom = _zoom;
    _gestureStartOffset = _offset;
    _gestureStartFocalPoint = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size frame) {
    final rotated = _rotatedImageSize();
    setState(() {
      _zoom = (_gestureStartZoom * details.scale).clamp(1.0, _maxUserZoom).toDouble();
      final displayed = Size(rotated.width * _baseScale * _zoom, rotated.height * _baseScale * _zoom);
      final delta = details.localFocalPoint - _gestureStartFocalPoint;
      _offset = _clampOffset(_gestureStartOffset + delta, frame, displayed);
    });
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // Render at a fixed output width regardless of the device's own
      // pixel ratio, so the uploaded banner always has decent resolution.
      final pixelRatio = _outputWidth / boundary.size.width;
      final rendered = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final out = File(
        '${Directory.systemTemp.path}/banner_crop_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await out.writeAsBytes(bytes, flush: true);
      if (mounted) Navigator.of(context).pop(out.path);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frameSize(context);
    if (_image != null && !_initialized) {
      _centerImage(frame);
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('crop_banner_title')),
        actions: [
          IconButton(
            onPressed: (_initialized && !_saving) ? () => _rotate(frame) : null,
            icon: const Icon(Icons.rotate_90_degrees_ccw_outlined),
            tooltip: context.tr('crop_banner_rotate'),
          ),
          TextButton(
            onPressed: (_initialized && !_saving) ? _confirm : null,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.tr('crop_banner_confirm')),
          ),
        ],
      ),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: frame.width,
                      height: frame.height,
                      child: ClipRect(
                        child: GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: (details) => _onScaleUpdate(details, frame),
                          child: RepaintBoundary(
                            key: _boundaryKey,
                            child: Stack(
                              children: [
                                Positioned(
                                  left: _offset.dx,
                                  top: _offset.dy,
                                  width: _rotatedImageSize().width * _baseScale * _zoom,
                                  height: _rotatedImageSize().height * _baseScale * _zoom,
                                  child: RotatedBox(
                                    quarterTurns: _quarterTurns,
                                    child: SizedBox(
                                      width: _image!.width * _baseScale * _zoom,
                                      height: _image!.height * _baseScale * _zoom,
                                      child: RawImage(image: _image, fit: BoxFit.fill),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    context.tr('crop_banner_hint'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }
}
