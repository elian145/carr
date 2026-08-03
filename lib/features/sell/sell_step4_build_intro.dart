part of 'sell_flow.dart';

mixin _SellStep4BuildIntro on _SellStep4Logic {
  List<Widget> _sellStep4BuildIntroSection() {
    final loc = AppLocalizations.of(context)!;

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kFilterAccentColor.withValues(alpha: 0.1),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: kFilterAccentColor.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.photo_library,
              size: 48,
              color: kFilterAccentColor,
            ),
            const SizedBox(height: 12),
            Text(
              loc.photosVideosTitle,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ];
  }
}
