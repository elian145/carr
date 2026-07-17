import 'dart:io';

import 'package:flutter/material.dart';

import 'listing_image_media.dart';

class VerticalCropResult {
  const VerticalCropResult(this.focusY);

  /// Null means use automatic positioning.
  final double? focusY;
}

/// Non-destructive vertical focal-point editor for a cover-fit listing image.
class VerticalCropEditor extends StatefulWidget {
  const VerticalCropEditor({
    super.key,
    required this.media,
    required this.networkUrl,
    this.frameAspectRatio = 1.1,
  });

  final dynamic media;
  final String Function(String source) networkUrl;
  final double frameAspectRatio;

  static Future<VerticalCropResult?> show(
    BuildContext context, {
    required dynamic media,
    required String Function(String source) networkUrl,
  }) {
    return Navigator.of(context).push<VerticalCropResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            VerticalCropEditor(media: media, networkUrl: networkUrl),
      ),
    );
  }

  @override
  State<VerticalCropEditor> createState() => _VerticalCropEditorState();
}

class _VerticalCropEditorState extends State<VerticalCropEditor> {
  late double _focusY;
  bool _automatic = false;

  double get _automaticFocus {
    final width = ListingImageMedia.width(widget.media);
    final height = ListingImageMedia.height(widget.media);
    return width != null && height != null && height > width * 1.08 ? 0.7 : 0.5;
  }

  @override
  void initState() {
    super.initState();
    final saved = ListingImageMedia.focusY(widget.media);
    _automatic = saved == null;
    _focusY = saved ?? _automaticFocus;
  }

  Widget _image() {
    final source = ListingImageMedia.source(widget.media);
    final alignment = Alignment(0, _focusY * 2 - 1);
    final local = ListingImageMedia.localFile(widget.media);
    if (local != null && File(local.path).existsSync()) {
      return Image.file(
        File(local.path),
        fit: BoxFit.cover,
        alignment: alignment,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return Image.network(
      widget.networkUrl(source),
      fit: BoxFit.cover,
      alignment: alignment,
      width: double.infinity,
      height: double.infinity,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust photo'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              VerticalCropResult(_automatic ? null : _focusY),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Drag vertically to choose how the photo appears.'),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: widget.frameAspectRatio,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = ListingImageMedia.width(widget.media);
                      final height = ListingImageMedia.height(widget.media);
                      final sourceAspect = width != null && height != null
                          ? width / height
                          : null;
                      final overflow = sourceAspect == null
                          ? constraints.maxHeight
                          : sourceAspect < widget.frameAspectRatio
                          ? constraints.maxWidth / sourceAspect -
                                constraints.maxHeight
                          : 0.0;
                      return GestureDetector(
                        onVerticalDragUpdate: overflow > 0
                            ? (details) {
                                setState(() {
                                  _automatic = false;
                                  _focusY =
                                      (_focusY - details.delta.dy / overflow)
                                          .clamp(0.0, 1.0);
                                });
                              }
                            : null,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _image(),
                              IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _automatic = true;
                  _focusY = _automaticFocus;
                }),
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Use automatic crop'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
