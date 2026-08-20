import 'dart:async';
import '../../theme/app_colors.dart';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/first_run_prefs.dart';
import '../carzo_shared.dart' show productionNavigatorKey;

/// Shows a short first-run tour once, then yields to [child] (UX-04).
///
/// The last step prompts signup/login; guests can continue without an account.
class FirstRunOnboardingGate extends StatefulWidget {
  const FirstRunOnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  State<FirstRunOnboardingGate> createState() => _FirstRunOnboardingGateState();
}

class _FirstRunOnboardingGateState extends State<FirstRunOnboardingGate> {
  bool _loading = true;
  bool _showTour = false;
  int _page = 0;
  final _controller = PageController();

  static const _accent = AppColors.brandOrange;

  /// Index of the final signup/login prompt (after the feature pages).
  static const _authPageIndex = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Widget/integration tests bind a fake HTTP client — skip the tour.
    if (ApiService.isTestHttpClientBound) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _showTour = false;
      });
      return;
    }
    final done = await FirstRunPrefs.isComplete();
    // Returning users with a stored session should not see the auth prompt.
    final alreadySignedIn = ApiService.isAuthenticated;
    if (alreadySignedIn && !done) {
      await FirstRunPrefs.markComplete();
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _showTour = !done && !alreadySignedIn;
    });
  }

  Future<void> _finish({bool openLogin = false}) async {
    await FirstRunPrefs.markComplete();
    if (!mounted) return;
    setState(() => _showTour = false);
    if (openLogin) {
      // Gate sits above the navigator (MaterialApp.builder); use the key.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        productionNavigatorKey.currentState?.pushNamed('/login');
      });
    }
  }

  void _goToAuthPage() {
    _controller.animateToPage(
      _authPageIndex,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _next(int pageCount) {
    if (_page >= pageCount - 1) {
      unawaited(_finish());
      return;
    }
    if (_page == _authPageIndex - 1) {
      _goToAuthPage();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return widget.child;
    if (!_showTour) return widget.child;

    final l = AppLocalizations.of(context)!;
    final featurePages = <_TourPage>[
      _TourPage(
        icon: Icons.search_rounded,
        title: l.onboardingBrowseTitle,
        body: l.onboardingBrowseBody,
      ),
      _TourPage(
        icon: Icons.favorite_rounded,
        title: l.onboardingFavoritesTitle,
        body: l.onboardingFavoritesBody,
      ),
      _TourPage(
        icon: Icons.add_circle_outline_rounded,
        title: l.onboardingSellTitle,
        body: l.onboardingSellBody,
      ),
    ];
    final pageCount = featurePages.length + 1; // + auth prompt
    final onAuthPage = _page >= _authPageIndex;

    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? Colors.white : const Color(0xFF121212);
    final ink = isLight ? const Color(0xFF1A1A1A) : const Color(0xFFECECEC);
    final muted = isLight ? Colors.grey.shade600 : Colors.white70;

    return Material(
      color: bg,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onAuthPage
                    ? () => unawaited(_finish())
                    : _goToAuthPage,
                child: Text(
                  onAuthPage ? l.onboardingContinueAsGuest : l.onboardingSkip,
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pageCount,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  if (index == _authPageIndex) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(
                              Icons.person_outline_rounded,
                              size: 44,
                              color: _accent,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            l.onboardingAuthTitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: ink,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            l.onboardingAuthBody,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.45,
                              color: muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final page = featurePages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(page.icon, size: 44, color: _accent),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: ink,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.45,
                            color: muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pageCount, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? _accent : _accent.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: onAuthPage
                  ? Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () =>
                                unawaited(_finish(openLogin: true)),
                            child: Text(
                              l.loginAction,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: TextButton(
                            onPressed: () => unawaited(_finish()),
                            child: Text(
                              l.onboardingContinueAsGuest,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: muted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => _next(pageCount),
                        child: Text(
                          l.onboardingNext,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourPage {
  const _TourPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}
