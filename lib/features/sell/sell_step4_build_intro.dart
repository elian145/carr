part of 'sell_flow.dart';

mixin _SellStep4BuildIntro on _SellStep4Logic {
  List<Widget> _sellStep4BuildIntroSection() {
    return [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF6B00).withValues(alpha: 0.1), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFFFF6B00).withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Icon(Icons.photo_library, size: 48, color: Color(0xFFFF6B00)),
                SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context)!.addPhotos,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.addMorePhotos,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          SizedBox(height: 24),

          // Image Processing Status
          if (_imagesProcessed)
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.blur_on, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      _trLegacyText(
                        context,
                        'Images Processed',
                        ar: 'تمت معالجة الصور',
                        ku: 'وێنەکان پرۆسێس کران',
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _trLegacyText(
                          context,
                          'License plates have been blurred.',
                          ar: 'تم تمويه لوحات المركبات.',
                          ku: 'ژمارەی تابلۆکان شاردراون.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    ];
  }
}
