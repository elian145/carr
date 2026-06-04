import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../prefs/sell_draft_media_persistence.dart';

/// One image in a listing card carousel (network URL or local file).
class ListingCardImageSlot {
  const ListingCardImageSlot.network(this.url) : filePath = null;
  const ListingCardImageSlot.file(this.filePath) : url = null;

  final String? url;
  final String? filePath;
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
          (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '')
              .toString()
              .trim();
      return s.isEmpty ? null : s;
    }
    final s = it?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static ListingCardImageSlot? _slotForSource(
    String raw,
    String Function(String) resolveNetworkUrl,
  ) {
    if (raw.isEmpty) return null;
    if (SellDraftMediaPersistence.isLocalMediaPath(raw)) {
      final path = SellDraftMediaPersistence.localMediaPath(raw);
      if (File(path).existsSync()) {
        return ListingCardImageSlot.file(path);
      }
      return null;
    }
    final full = resolveNetworkUrl(raw);
    if (full.isEmpty) return null;
    return ListingCardImageSlot.network(full);
  }

  static List<ListingCardImageSlot> collectFromCar(
    Map car, {
    required String Function(String) resolveNetworkUrl,
  }) {
    final slots = <ListingCardImageSlot>[];
    final seen = <String>{};

    final primary = (car['image_url'] ?? '').toString().trim();
    if (primary.isNotEmpty) {
      final slot = _slotForSource(primary, resolveNetworkUrl);
      if (slot != null) _addSlot(slots, seen, slot);
    }

    final imgs =
        (car['images'] is List) ? (car['images'] as List) : const <dynamic>[];

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
      final slot = _slotForSource(s, resolveNetworkUrl);
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
          final slot = _slotForSource(s, resolveNetworkUrl);
          if (slot != null) _addSlot(slots, seen, slot);
        }
        break;
      }
    }

    return slots;
  }

  static Widget buildCarouselImage(
    ListingCardImageSlot slot, {
    required Widget Function(String url, {BoxFit fit}) networkBuilder,
    BoxFit fit = BoxFit.cover,
  }) {
    final path = slot.filePath;
    if (path != null) {
      return Image.file(
        File(path),
        fit: fit,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.broken_image,
          size: 48,
          color: Colors.grey[500],
        ),
      );
    }
    return networkBuilder(slot.url!, fit: fit);
  }
}
