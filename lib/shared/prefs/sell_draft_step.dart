import 'dart:math' as math;

/// Robust step index from JSON / route maps (`int`, `double`, `1.0` strings).
int readSellDraftStepDynamic(dynamic raw, {int maxIdx = 4}) {
  if (raw == null) return 0;
  if (raw is int) return raw.clamp(0, maxIdx);
  if (raw is double) {
    if (raw.isNaN || raw.isInfinite) return 0;
    return raw.round().clamp(0, maxIdx);
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return 0;
  final asDouble = double.tryParse(s);
  if (asDouble != null) {
    return asDouble.round().clamp(0, maxIdx);
  }
  return int.tryParse(s)?.clamp(0, maxIdx) ?? 0;
}

/// Prefer the higher of JSON snapshot step and prefs step when they disagree.
int mergeSellDraftStep({int? jsonStep, int? prefsStep, int maxIdx = 4}) {
  final j = (jsonStep ?? 0).clamp(0, maxIdx);
  if (prefsStep == null) return j;
  final p = prefsStep.clamp(0, maxIdx);
  return j > p ? j : p;
}

int maxSellDraftStep(int a, int b, [int c = 0, int maxIdx = 4]) {
  return math.max(
    math.max(a.clamp(0, maxIdx), b.clamp(0, maxIdx)),
    c.clamp(0, maxIdx),
  );
}
