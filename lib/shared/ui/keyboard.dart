import 'package:flutter/widgets.dart';

void dismissAnyKeyboard([BuildContext? context]) {
  final focus = FocusManager.instance.primaryFocus;
  if (focus != null && focus.hasFocus) {
    focus.unfocus();
  }
  if (context != null && context.mounted) {
    FocusScope.of(context).unfocus();
  }
}

/// Moves focus to the next traversable control (A-05 form keyboard chain).
void focusNextField(BuildContext context) {
  FocusScope.of(context).nextFocus();
}

/// Requests focus on [node] after the current frame (safe after setState / navigation).
void requestFocusAfterFrame(FocusNode node) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (node.canRequestFocus) {
      node.requestFocus();
    }
  });
}

/// Dismisses the keyboard when the user taps outside a focused field.
class KeyboardDismissOnTap extends StatelessWidget {
  const KeyboardDismissOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => dismissAnyKeyboard(context),
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
