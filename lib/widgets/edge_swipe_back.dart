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

class _EdgeSwipeBackState extends State<EdgeSwipeBack>
    with SingleTickerProviderStateMixin {
  double _dragDx = 0;
  bool _popped = false;
  late final AnimationController _settleController;
  Animation<double>? _settleAnimation;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

  bool _canPop() {
    final nav = widget.navigatorKey.currentState;
    return nav != null && nav.canPop();
  }

  void _reset() {
    _settleController.stop();
    _settleAnimation = null;
    _dragDx = 0;
    _popped = false;
  }

  void _animateTo(double target, {required Duration duration, VoidCallback? onDone}) {
    _settleController
      ..stop()
      ..duration = duration;
    _settleAnimation = Tween<double>(
      begin: _dragDx,
      end: target,
    ).animate(CurvedAnimation(parent: _settleController, curve: Curves.easeOutCubic))
      ..addListener(() {
        if (!mounted) return;
        setState(() {
          _dragDx = _settleAnimation!.value;
        });
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && onDone != null) {
          onDone();
        }
      });
    _settleController.forward(from: 0);
  }

  void _animateBackToStart() {
    if (_dragDx <= 0) {
      _reset();
      return;
    }
    _animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      onDone: _reset,
    );
  }

  void _maybePop() {
    if (_popped) return;
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    if (!nav.canPop()) return;

    _popped = true;
    final width = MediaQuery.sizeOf(context).width;
    final target = width.clamp(280.0, 1200.0);
    _animateTo(
      target,
      duration: const Duration(milliseconds: 140),
      onDone: () async {
        await nav.maybePop();
        if (mounted) {
          setState(() {
            _reset();
          });
        }
      },
    );
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
                _settleController.stop();
                _dragDx = (_dragDx + details.delta.dx).clamp(0.0, double.infinity);
                setState(() {});
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
                } else {
                  _animateBackToStart();
                }
              }
              ..onCancel = () {
                if (_popped) return;
                _animateBackToStart();
              };
          },
        ),
      },
      child: Transform.translate(
        offset: Offset(_dragDx, 0),
        child: widget.child,
      ),
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

