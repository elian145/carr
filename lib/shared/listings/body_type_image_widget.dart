import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;

List<double> _tintColorMatrix(Color color) {
  const double lR = 0.2126;
  const double lG = 0.7152;
  const double lB = 0.0722;
  final double r = color.r;
  final double g = color.g;
  final double b = color.b;
  return [
    lR * r, lG * r, lB * r, 0, 0,
    lR * g, lG * g, lB * g, 0, 0,
    lR * b, lG * b, lB * b, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

final Map<String, Future<ui.Image>> _whiteKeyedCache = {};

Future<ui.Image> _decodePngWithWhiteTransparent(String assetPath) async {
  final services.ByteData data = await services.rootBundle.load(assetPath);
  final Uint8List bytes = data.buffer.asUint8List();
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image image = frame.image;
  final ByteData? raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (raw == null) {
    throw Exception('Failed to read image bytes');
  }
  final Uint8List rgba = raw.buffer.asUint8List();
  const int threshold = 250;
  for (int i = 0; i < rgba.length; i += 4) {
    final int r = rgba[i];
    final int g = rgba[i + 1];
    final int b = rgba[i + 2];
    if (r >= threshold && g >= threshold && b >= threshold) {
      rgba[i + 3] = 0;
    }
  }
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    image.width,
    image.height,
    ui.PixelFormat.rgba8888,
    (ui.Image img) => completer.complete(img),
  );
  return completer.future;
}

class _WhiteKeyedImage extends StatefulWidget {
  const _WhiteKeyedImage({
    required this.assetPath,
    required this.svgFallbackPath,
  });

  final String assetPath;
  final String svgFallbackPath;

  @override
  State<_WhiteKeyedImage> createState() => _WhiteKeyedImageState();
}

class _WhiteKeyedImageState extends State<_WhiteKeyedImage> {
  Future<ui.Image>? _futureImage;

  @override
  void initState() {
    super.initState();
    _futureImage = (_whiteKeyedCache[widget.assetPath] ??=
        _decodePngWithWhiteTransparent(widget.assetPath));
  }

  @override
  void didUpdateWidget(covariant _WhiteKeyedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      setState(() {
        _futureImage = (_whiteKeyedCache[widget.assetPath] ??=
            _decodePngWithWhiteTransparent(widget.assetPath));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: _futureImage,
      builder: (context, snap) {
        if (snap.hasData) {
          return RawImage(
            image: snap.data,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          );
        }
        if (snap.hasError) {
          return Image.asset(
            widget.assetPath,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Icon(
              Icons.directions_car,
              color: Color(0xFF707070),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Body-type PNG with white keyed to transparent (home filters + sell flow).
Widget buildBodyTypeImage(String assetPath) {
  late final String pngAssetPath;
  late final String svgFallbackPath;

  if (assetPath.toLowerCase().endsWith('.png')) {
    pngAssetPath = assetPath;
    svgFallbackPath = assetPath
        .replaceFirst('/body_types_png/', '/body_types_clean/')
        .replaceAll('.png', '.svg');
  } else {
    svgFallbackPath = assetPath;
    pngAssetPath = assetPath
        .replaceFirst('/body_types_clean/', '/body_types_png/')
        .replaceAll('.svg', '.png');
  }

  return ColorFiltered(
    colorFilter: ColorFilter.matrix(_tintColorMatrix(const Color(0xFF707070))),
    child: _WhiteKeyedImage(
      assetPath: pngAssetPath,
      svgFallbackPath: svgFallbackPath,
    ),
  );
}
