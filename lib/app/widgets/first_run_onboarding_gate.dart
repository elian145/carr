import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/first_run_prefs.dart';

/// Shows a short first-run tour once, then yields to [child] (UX-04).
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

  static const _accent = Color(0xFFFF6B00);

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
    if (!mounted) return;
    setState(() {
      _loading = false;
      _showTour = !done;
    });
  }

  Future<void> _finish() async {
    await FirstRunPrefs.markComplete();
    if (!mounted) return;
    setState(() => _showTour = false);
  }

  void _next(int pageCount) {
    if (_page >= pageCount - 1) {
      unawaited(_finish());
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
    final pages = <_TourPage>[
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
                onPressed: () => unawaited(_finish()),
                child: Text(l.onboardingSkip),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  final page = pages[index];
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
              children: List.generate(pages.length, (i) {
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
              child: SizedBox(
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
                  onPressed: () => _next(pages.length),
                  child: Text(
                    _page >= pages.length - 1
                        ? l.onboardingGetStarted
                        : l.onboardingNext,
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
