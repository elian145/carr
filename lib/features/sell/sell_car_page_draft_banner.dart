part of 'sell_flow.dart';

mixin _SellCarPageDraftBanner on _SellCarPageDraftPersist {
  Widget _buildDraftBanner() {
    if (!_hasDraftSnapshot || _hideDraftBanner) {
      return const SizedBox.shrink();
    }
    final labels = <String>[
      'Step 1: Basic info',
      'Step 2: Details',
      'Step 3: Pricing',
      'Step 4: Photos',
      'Step 5: Review',
    ];
    final stepLabel = labels[_draftPreviewStep.clamp(0, 4).toInt()];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.drafts_outlined, color: Color(0xFFFF6B00)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _trLegacyText(
                            context,
                            'Draft in progress',
                            ar: 'مسودة قيد التقدم',
                            ku: 'ڕەشنووسی لە پێشکەوتن',
                          ),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(stepLabel, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _draftTitle(_draftPreviewCarData ?? carData),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                'Continue here to finish the listing, or discard it if you want to start over.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _clearAllSellDrafts();
                        if (!mounted) return;
                        setState(() {
                          currentStep = 0;
                          carData = {};
                          completedSteps.clear();
                          _hasDraftSnapshot = false;
                          _draftPreviewStep = 0;
                          _draftPreviewCarData = null;
                          _sellPageResetToken++;
                        });
                        if (_pageController.hasClients) {
                          _pageController.jumpToPage(0);
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Discard draft'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => unawaited(_resumeSellDraft()),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
