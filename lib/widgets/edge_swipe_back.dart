import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// When true, the outgoing route keeps its edge-swipe offset and skips the
/// theme pop slide until cleared after [Navigator.maybePop].
class NavigationPopCoordinator {
  NavigationPopCoordinator._();

  static bool suppressNextRoutePopTransition = false;
}

/// Drives interactive edge-swipe offset for the top route's page transition.
class EdgeSwipeBackCoordinator extends ChangeNotifier {
  EdgeSwipeBackCoordinator._();

  static final EdgeSwipeBackCoordinator instance = EdgeSwipeBackCoordinator._();

  double _dragDx = 0;
  double _exitLatchFraction = 0;

  double get dragDx => _dragDx;

  /// Fraction of screen width held after an edge-swipe pop until the route
  /// transition finishes, so the page does not snap back on-screen.
  double get exitLatchFraction => _exitLatchFraction;

  void setDragDx(double dx) {
    final clamped = dx.clamp(0.0, double.infinity);
    if (_dragDx == clamped) return;
    _dragDx = clamped;
    notifyListeners();
  }

  void latchExitFraction(double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    if (_exitLatchFraction == clamped) return;
    _exitLatchFraction = clamped;
    notifyListeners();
  }

  void reset() {
    if (_dragDx == 0 && _exitLatchFraction == 0) return;
    _dragDx = 0;
    _exitLatchFraction = 0;
    notifyListeners();
  }
}

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
  static const Duration _popTransitionClearDelay = Duration(milliseconds: 320);

  bool _popped = false;
  late final AnimationController _settleController;
  Animation<double>? _settleAnimation;
  final EdgeSwipeBackCoordinator _coordinator = EdgeSwipeBackCoordinator.instance;

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
    _coordinator.reset();
    _popped = false;
  }

  void _animateTo(
    double target, {
    required Duration duration,
    VoidCallback? onDone,
  }) {
    _settleController
      ..stop()
      ..duration = duration;
    _settleAnimation = Tween<double>(
      begin: _coordinator.dragDx,
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _settleController,
        curve: Curves.easeOutCubic,
      ),
    )..addListener(() {
        if (!mounted) return;
        _coordinator.setDragDx(_settleAnimation!.value);
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && onDone != null) {
          onDone();
        }
      });
    _settleController.forward(from: 0);
  }

  void _animateBackToStart() {
    if (_coordinator.dragDx <= 0) {
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
      onDone: () {
        final width = MediaQuery.sizeOf(context).width;
        _coordinator.latchExitFraction(_coordinator.dragDx / width);
        NavigationPopCoordinator.suppressNextRoutePopTransition = true;
        _settleController.stop();
        _settleAnimation = null;
        nav.maybePop().then((didPop) {
          if (!mounted) return;
          if (!didPop) {
            NavigationPopCoordinator.suppressNextRoutePopTransition = false;
            _reset();
            return;
          }
          Future<void>.delayed(_popTransitionClearDelay, () {
            if (!mounted) return;
            NavigationPopCoordinator.suppressNextRoutePopTransition = false;
            _reset();
          });
        });
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
                _coordinator.setDragDx(
                  _coordinator.dragDx + details.delta.dx,
                );
                if (_coordinator.dragDx >= widget.triggerDistance) {
                  _maybePop();
                }
              }
              ..onEnd = (details) {
                if (_popped) return;
                final v = details.primaryVelocity ?? 0;
                if (_coordinator.dragDx >= widget.triggerDistance ||
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
    if (!_canStart()) return;
    if (event.position.dx > _edgeWidth) return;
    super.addAllowedPointer(event);
  }
}
