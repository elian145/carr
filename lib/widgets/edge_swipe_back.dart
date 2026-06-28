import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../navigation/app_page_route.dart';

class EdgeSwipeBack extends StatefulWidget {
  const EdgeSwipeBack({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.edgeWidth = 20,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final double edgeWidth;

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> {
  _AppBackGestureController? _gestureController;

  bool _canPop() {
    final nav = widget.navigatorKey.currentState;
    return nav != null && nav.canPop();
  }

  AppPageRoute<dynamic>? _topAppPageRoute(NavigatorState navigator) {
    AppPageRoute<dynamic>? top;
    navigator.popUntil((route) {
      if (route.isCurrent && route is AppPageRoute) {
        top = route;
      }
      return true;
    });
    return top;
  }

  void _onDragStart() {
    final nav = widget.navigatorKey.currentState;
    if (nav == null || !nav.canPop()) return;

    final route = _topAppPageRoute(nav);
    final controller = route?.routeAnimationController;
    if (route == null || controller == null) return;

    nav.didStartUserGesture();
    _gestureController = _AppBackGestureController(
      navigator: nav,
      route: route,
      animationController: controller,
      screenWidth: MediaQuery.sizeOf(context).width,
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _gestureController?.dragUpdate(details.delta.dx);
  }

  void _onDragEnd(DragEndDetails details) {
    _gestureController?.dragEnd(details.primaryVelocity ?? 0);
    _gestureController = null;
  }

  void _onDragCancel() {
    _gestureController?.dragEnd(0);
    _gestureController = null;
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
            recognizer.onStart = (_) => _onDragStart();
            recognizer.onUpdate = _onDragUpdate;
            recognizer.onEnd = _onDragEnd;
            recognizer.onCancel = _onDragCancel;
          },
        ),
      },
      child: widget.child,
    );
  }
}

class _AppBackGestureController {
  _AppBackGestureController({
    required this.navigator,
    required this.route,
    required this.animationController,
    required this.screenWidth,
  });

  static const double _minFlingVelocity = 1.0;
  static const Duration _droppedPageAnimationDuration =
      Duration(milliseconds: 180);

  final NavigatorState navigator;
  final AppPageRoute<dynamic> route;
  final AnimationController animationController;
  final double screenWidth;

  void dragUpdate(double deltaPx) {
    animationController.value -= deltaPx / screenWidth;
  }

  void dragEnd(double velocityPxPerSec) {
    final velocity = velocityPxPerSec / screenWidth;
    final isCurrent = route.isCurrent;
    final bool animateForward;

    if (!isCurrent) {
      animateForward = route.isActive;
    } else if (velocity.abs() >= _minFlingVelocity) {
      animateForward = velocity <= 0;
    } else {
      animateForward = animationController.value > 0.5;
    }

    if (animateForward) {
      animationController.animateTo(
        1.0,
        duration: _droppedPageAnimationDuration,
        curve: Curves.fastEaseInToSlowEaseOut,
      );
    } else {
      if (isCurrent) {
        navigator.pop();
      }
      if (animationController.isAnimating) {
        animationController.animateBack(
          0.0,
          duration: _droppedPageAnimationDuration,
          curve: Curves.fastEaseInToSlowEaseOut,
        );
      }
    }

    if (animationController.isAnimating) {
      void stopGesture(AnimationStatus status) {
        navigator.didStopUserGesture();
        animationController.removeStatusListener(stopGesture);
      }

      animationController.addStatusListener(stopGesture);
    } else {
      navigator.didStopUserGesture();
    }
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
