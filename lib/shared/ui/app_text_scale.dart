import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'system_display_lock.dart';

/// Effective (already clamped by [SystemDisplayLock]) system text scale for
/// body-sized text, never below 1.0.
///
/// Use this to size the *fixed* parts of a layout (row heights, badge heights,
/// reserved title blocks) so they grow together with the text instead of
/// clipping it. Text widgets themselves should simply inherit the scaler from
/// [MediaQuery]; never pass `TextScaler.noScaling` to content text.
double appTextScaleOf(BuildContext context) {
  return math.max(
    1.0,
    SystemDisplayLock.textScaleFactorOf(MediaQuery.textScalerOf(context)),
  );
}
