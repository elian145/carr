part of 'dealer_location_picker_page.dart';

mixin _DealerLocationPickerPageCore on _DealerLocationPickerPageLoad {
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: Text(_tr('Map location', ar: 'موقع الخريطة', ku: 'شوێنی نەخشە'))),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              _tr(
                'The in-app map picker is available on Android and iOS. On web, set latitude and longitude in the edit form, or open Google Maps in your browser to copy coordinates.',
                ar: 'محدد الموقع داخل التطبيق متاح على Android و iOS. على الويب، أدخل خط العرض وخط الطول في نموذج التعديل أو افتح خرائط Google في المتصفح لنسخ الإحداثيات.',
                ku: 'هەڵبژێرەری شوێنی ناو ئەپ لە Android و iOS بەردەستە. لە وێبدا، لاتیتوود و لۆنگیتوود لە فۆڕمی دەستکاریکردندا دابنێ یان نەخشەی گووگڵ لە وێبگەڕەکەت بکەرەوە بۆ کۆپیکردنی کۆئۆردینات.',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Pin dealership location', ar: 'تثبيت موقع المعرض', ku: 'پینی شوێنی نمایشگا')),
        actions: [
          TextButton(
            onPressed: _confirmFromMap,
            child: Text(_tr('USE THIS PIN', ar: 'استخدم هذا الدبوس', ku: 'ئەم پینە بەکاربهێنە')),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _markerPosition,
              zoom: 15,
            ),
            markers: _markers,
            onMapCreated: _onMapCreated,
            onTap: (p) => setState(() => _markerPosition = p),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                      child: Row(
                        children: [
                          const Icon(Icons.search_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _searchPlace(),
                              decoration: InputDecoration(
                                hintText: _tr('Search in Google Maps', ar: 'ابحث في خرائط Google', ku: 'لە نەخشەی گووگڵ بگەڕێ'),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          if (_searchController.text.trim().isNotEmpty)
                            IconButton(
                              tooltip: _tr('Clear', ar: 'مسح', ku: 'پاککردنەوە'),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _predictions = const []);
                              },
                              icon: const Icon(Icons.close),
                            ),
                          FilledButton(
                            onPressed: (_searching || !_placesReady)
                                ? null
                                : () => _searchPlace(),
                            child: _searching
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _placesReady
                                        ? _tr('Search', ar: 'بحث', ku: 'گەڕان')
                                        : _tr('Loading', ar: 'جارٍ التحميل', ku: 'بار دەبێت'),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!_placesReady) ...[
                    const SizedBox(height: 8),
                    Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Row(
                          children: [
                            if (_placesInitError == null) ...[
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(_tr('Loading Google Maps search...', ar: 'جارٍ تحميل بحث خرائط Google...', ku: 'بارکردنی گەڕانی نەخشەی گووگڵ...')),
                              ),
                            ] else ...[
                              const Icon(Icons.warning_amber_rounded),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _tr(
                                    'Search unavailable. Check Places API + billing/key restrictions.',
                                    ar: 'البحث غير متاح. تحقق من Places API والفوترة وقيود المفتاح.',
                                    ku: 'گەڕان بەردەست نییە. Places API و billing و قەیدەکانی key بپشکنە.',
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              TextButton(
                                onPressed: _initPlaces,
                                child: Text(AppLocalizations.of(context)?.retryAction ?? 'Retry'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_predictions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Material(
                      elevation: 3,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      color: Theme.of(context).colorScheme.surface,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _predictions.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final p = _predictions[i];
                            return ListTile(
                              leading:
                                  const Icon(Icons.place_outlined, size: 22),
                              title: Text(
                                (p.title ?? '').trim().isEmpty
                                    ? (p.description ?? _tr('Result', ar: 'نتيجة', ku: 'ئەنجام'))
                                    : p.title!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: (p.description ?? '').trim().isEmpty
                                  ? null
                                  : Text(
                                      p.description!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onTap: () => _pickPrediction(p),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _confirmFromMap,
        icon: const Icon(Icons.check),
        label: Text(_tr('Save pin', ar: 'حفظ الدبوس', ku: 'پاشەکەوتکردنی پین')),
      ),
    );
  }
}
