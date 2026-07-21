import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/widgets/listing_network_image.dart';
import '../prefs/sell_draft_media_persistence.dart';
import 'listing_image_media.dart';

/// One image in a listing card carousel (network URL or local file).
class ListingCardImageSlot {
  const ListingCardImageSlot.network(this.url, {this.metadata})
    : filePath = null;
  const ListingCardImageSlot.file(this.filePath, {this.metadata}) : url = null;

  final String? url;
  final String? filePath;
  final Map<String, dynamic>? metadata;
}

/// Resolves listing card carousel media from API listings and sell drafts.
class ListingCardMedia {
  ListingCardMedia._();

  static void _addSlot(
    List<ListingCardImageSlot> slots,
    Set<String> seen,
    ListingCardImageSlot slot,
  ) {
    final key = slot.filePath ?? slot.url ?? '';
    if (key.isEmpty || seen.contains(key)) return;
    seen.add(key);
    slots.add(slot);
  }

  static String? _stringFromImageItem(dynamic it) {
    if (it is XFile) return it.path;
    if (it is Map) {
      final s =
          (it['source'] ??
                  it['image_url'] ??
                  it['url'] ??
                  it['path'] ??
                  it['src'] ??
                  '')
              .toString()
              .trim();
      return s.isEmpty ? null : s;
    }
    final s = it?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static ListingCardImageSlot? _slotForSource(
    String raw,
    String Function(String) resolveNetworkUrl, {
    Map<String, dynamic>? metadata,
  }) {
    if (raw.isEmpty) return null;
    if (SellDraftMediaPersistence.isLocalMediaPath(raw)) {
      final path = SellDraftMediaPersistence.localMediaPath(raw);
      if (File(path).existsSync()) {
        return ListingCardImageSlot.file(path, metadata: metadata);
      }
      return null;
    }
    final full = resolveNetworkUrl(raw);
    if (full.isEmpty) return null;
    return ListingCardImageSlot.network(full, metadata: metadata);
  }

  static List<ListingCardImageSlot> collectFromCar(
    Map car, {
    required String Function(String) resolveNetworkUrl,
  }) {
    final slots = <ListingCardImageSlot>[];
    final seen = <String>{};

    final primary = (car['image_url'] ?? '').toString().trim();
    if (primary.isNotEmpty) {
      Map<String, dynamic>? primaryMetadata;
      final rawImages = car['images'] is List
          ? car['images'] as List
          : const <dynamic>[];
      for (final item in rawImages) {
        if (item is Map &&
            resolveNetworkUrl(ListingImageMedia.source(item)) ==
                resolveNetworkUrl(primary)) {
          primaryMetadata = Map<String, dynamic>.from(item);
          break;
        }
      }
      final slot = _slotForSource(
        primary,
        resolveNetworkUrl,
        metadata: primaryMetadata,
      );
      if (slot != null) _addSlot(slots, seen, slot);
    }

    final imgs = (car['images'] is List)
        ? (car['images'] as List)
        : const <dynamic>[];

    for (final it in imgs) {
      if (it is Map &&
          (it['kind'] ?? '').toString().toLowerCase() == 'damage') {
        continue;
      }
      if (it is XFile) {
        if (File(it.path).existsSync()) {
          _addSlot(slots, seen, ListingCardImageSlot.file(it.path));
        }
        continue;
      }
      final s = _stringFromImageItem(it);
      if (s == null) continue;
      final slot = _slotForSource(
        s,
        resolveNetworkUrl,
        metadata: it is Map ? Map<String, dynamic>.from(it) : null,
      );
      if (slot != null) _addSlot(slots, seen, slot);
    }

    if (slots.isEmpty && imgs.isNotEmpty) {
      for (final e in imgs) {
        if (e is Map &&
            (e['kind'] ?? '').toString().toLowerCase() == 'damage') {
          continue;
        }
        if (e is XFile) {
          if (File(e.path).existsSync()) {
            _addSlot(slots, seen, ListingCardImageSlot.file(e.path));
          }
          break;
        }
        final s = _stringFromImageItem(e);
        if (s != null) {
          final slot = _slotForSource(
            s,
            resolveNetworkUrl,
            metadata: e is Map ? Map<String, dynamic>.from(e) : null,
          );
          if (slot != null) _addSlot(slots, seen, slot);
        }
        break;
      }
    }

    return slots;
  }

  static Widget buildCarouselImage(
    ListingCardImageSlot slot, {
    required Widget Function(String url, {BoxFit fit, Alignment alignment})
    networkBuilder,
    BoxFit fit = BoxFit.cover,
  }) {
    return _SmartListingCardImage(
      slot: slot,
      networkBuilder: networkBuilder,
      fit: fit,
    );
  }
}

class _SmartListingCardImage extends StatefulWidget {
  const _SmartListingCardImage({
    required this.slot,
    required this.networkBuilder,
    required this.fit,
  });

  final ListingCardImageSlot slot;
  final Widget Function(String url, {BoxFit fit, Alignment alignment})
  networkBuilder;
  final BoxFit fit;

  @override
  State<_SmartListingCardImage> createState() => _SmartListingCardImageState();
}

class _SmartListingCardImageState extends State<_SmartListingCardImage> {
  int? _width;
  int? _height;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _width = ListingImageMedia.width(widget.slot.metadata);
    _height = ListingImageMedia.height(widget.slot.metadata);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_width != null && _height != null) return;
    final ImageProvider provider = widget.slot.filePath != null
        ? FileImage(File(widget.slot.filePath!))
        : listingCachedNetworkImageProvider(widget.slot.url!);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      final width = info.image.width;
      final height = info.image.height;
      if (width == _width && height == _height) return;
      setState(() {
        _width = width;
        _height = height;
      });
    });
    _stream = stream;
    stream.addListener(_listener!);
  }

  @override
  void dispose() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metadata = ListingImageMedia.map(
      widget.slot.metadata ?? widget.slot.filePath ?? widget.slot.url,
      width: _width,
      height: _height,
      focusY: ListingImageMedia.focusY(widget.slot.metadata),
    );
    final alignment = ListingImageMedia.coverAlignment(metadata);
    final path = widget.slot.filePath;
    if (path != null) {
      return Image.file(
        File(path),
        fit: widget.fit,
        alignment: alignment,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.broken_image, size: 48, color: Colors.grey[500]),
      );
    }
    return widget.networkBuilder(
      widget.slot.url!,
      fit: widget.fit,
      alignment: alignment,
    );
  }
}
