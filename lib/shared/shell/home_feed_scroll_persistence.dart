import 'package:flutter/material.dart';

/// Persists home feed scroll when main tabs use route replacement.
class HomeFeedScrollPersistence {
  HomeFeedScrollPersistence._();

  static double? _pixels;

  static double get initialOffset => _pixels ?? 0;

  static void capture(ScrollController controller) {
    try {
      if (controller.hasClients) {
        final pos = controller.position;
        _pixels = pos.pixels.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      }
    } catch (_) {}
  }

  static void markTop() {
    _pixels = 0;
  }

  static void savePixels(double pixels) {
    _pixels = pixels;
  }
}
