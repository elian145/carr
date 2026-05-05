import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class EdgeSwipeBack extends StatefulWidget {
  const EdgeSwipeBack({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.edgeWidth = 20,
    this.triggerDistance = 120,
    this.triggerVelocity = 900,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Only swipes that begin within this many logical pixels from the left edge
  /// will be considered.
  final double edgeWidth;

  /// Minimum horizontal drag distance required to pop.
  final double triggerDistance;

  /// Minimum fling velocity (px/s) required to pop.
  final double triggerVelocity;

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> {
  double _dragDx = 0;
  bool _popped = false;

  bool _canPop() {
    final nav = widget.navigatorKey.currentState;
    return nav != null && nav.canPop();
  }

  void _reset() {
    _dragDx = 0;
    _popped = false;
  }

  void _maybePop() {
    if (_popped) return;
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    if (!nav.canPop()) return;

    _popped = true;
    nav.maybePop();
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _EdgeBackGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_EdgeBackGestureRecognizer>(
          () => _EdgeBackGestureRecognizer(
            canStart: _canPop,
            edgeWidth: widget.edgeWidth,
          ),
          (recognizer) {
            recognizer
              ..onStart = (_) {
                _reset();
              }
              ..onUpdate = (details) {
                if (_popped) return;
                _dragDx = (_dragDx + details.delta.dx).clamp(0.0, double.infinity);
                if (_dragDx >= widget.triggerDistance) {
                  _maybePop();
                }
              }
              ..onEnd = (details) {
                if (_popped) return;
                final v = details.primaryVelocity ?? 0;
                if (_dragDx >= widget.triggerDistance ||
                    v >= widget.triggerVelocity) {
                  _maybePop();
                }
                _reset();
              }
              ..onCancel = () {
                _reset();
              };
          },
        ),
      },
      child: widget.child,
    );
  }
}

class _EdgeBackGestureRecognizer extends HorizontalDragGestureRecognizer {
  _EdgeBackGestureRecognizer({
    required bool Function() canStart,
    required double edgeWidth,
  })  : _canStart = canStart,
        _edgeWidth = edgeWidth;

  final bool Function() _canStart;
  final double _edgeWidth;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // Global position: x==0 is the far-left edge of the screen.
    if (!_canStart()) return;
    if (event.position.dx > _edgeWidth) return;
    super.addAllowedPointer(event);
  }
}

