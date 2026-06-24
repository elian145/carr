part of 'edit_dealer_page.dart';

mixin _EditDealerPageBuildBody on _EditDealerPageSave {
  Widget _buildEditDealerBody(BuildContext context) {
    final logoUrl = buildMediaUrl((_currentLogo ?? '').trim());
    final coverUrl = buildMediaUrl((_currentCover ?? '').trim());
    final brightness = Theme.of(context).brightness;
    final cardShape = _pageCardShape(brightness);
    final isLightShell = brightness == Brightness.light;
    final dividerColor = isLightShell ? Colors.grey.shade200 : Colors.white12;
    final cardFill = isLightShell
        ? Colors.white
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.06),
            AppThemes.darkHomeShellBackground,
          );

      return Stack(
        children: [
          Container(
            decoration: AppThemes.shellBackgroundDecoration(
              Theme.of(context).brightness,
            ),
          ),
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                Card(
                  color: cardFill,
                  shadowColor: Colors.black54,
                  elevation: isLightShell ? 6 : 10,
                  shape: cardShape,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                          icon: Icons.photo_outlined,
                          title: _tr('Branding', ar: 'العلامة التجارية', ku: 'براندینگ'),
                          subtitle: _tr('Logo and cover image shown on your dealer page.', ar: 'يظهر الشعار وصورة الغلاف في صفحة الوكيل.', ku: 'لۆگۆ و وێنەی کاڤەر لە پەڕەی وەکیلت پیشان دەدرێت.'),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            height: 132,
                            width: double.infinity,
                            child: _buildBrandingCoverPreview(coverUrl),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Material(
                              elevation: 4,
                              shadowColor: Colors.black38,
                              shape: const CircleBorder(),
                              color: Theme.of(context).colorScheme.surface,
                              child: CircleAvatar(
                                radius: 28,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                backgroundImage: _logo != null
                                    ? FileImage(File(_logo!.path))
                                    : (logoUrl.isNotEmpty
                                        ? NetworkImage(logoUrl)
                                        : null),
                                child: _logo == null && logoUrl.isEmpty
                                    ? Icon(
                                        Icons.storefront_outlined,
                                        size: 26,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _brandingMediaButton(
                                onPressed: _saving ? null : _pickLogo,
                                icon: Icons.image_outlined,
                                selected: _logo != null,
                                label: _logo == null
                                    ? _tr('Change logo', ar: 'تغيير الشعار', ku: 'گۆڕینی لۆگۆ')
                                    : _tr('Logo selected', ar: 'تم اختيار الشعار', ku: 'لۆگۆ هەڵبژێردرا'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _brandingMediaButton(
                                onPressed: _saving ? null : _pickCover,
                                icon: Icons.photo_outlined,
                                selected: _cover != null,
                                label: _cover == null
                                    ? _tr('Change cover', ar: 'تغيير الغلاف', ku: 'گۆڕینی کاڤەر')
                                    : _tr('Cover selected', ar: 'تم اختيار الغلاف', ku: 'کاڤەر هەڵبژێردرا'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: cardFill,
                  shadowColor: Colors.black54,
                  elevation: isLightShell ? 6 : 10,
                  shape: cardShape,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                          icon: Icons.storefront_outlined,
                          title: _tr('Dealership details', ar: 'تفاصيل المعرض', ku: 'وردەکاری نمایشگا'),
                          subtitle: _tr('What buyers see on your dealer page.', ar: 'ما يراه المشترون في صفحة الوكيل.', ku: 'ئەوەی کڕیاران لە پەڕەی وەکیلت دەیبینن.'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _name,
                          style: _fieldTextStyle(isLightShell),
                          decoration: _fieldDecoration(
                            isLightShell,
                            label: _tr('Dealership name', ar: 'اسم المعرض', ku: 'ناوی نمایشگا'),
                            icon: Icons.badge_outlined,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? _tr('Dealership name is required', ar: 'اسم المعرض مطلوب', ku: 'ناوی نمایشگا پێویستە')
                              : null,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _location,
                          style: _fieldTextStyle(isLightShell),
                          decoration: _fieldDecoration(
                            isLightShell,
                            label: _tr('Dealership location', ar: 'موقع المعرض', ku: 'شوێنی نمایشگا'),
                            icon: Icons.location_on_outlined,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? _tr('Dealership location is required', ar: 'موقع المعرض مطلوب', ku: 'شوێنی نمایشگا پێویستە')
                              : null,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _description,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 1000,
                          style: _fieldTextStyle(isLightShell),
                          decoration: _fieldDecoration(
                            isLightShell,
                            label: _loc?.descriptionTitle ?? 'Description',
                            hint: _tr('Tell buyers about your dealership', ar: 'أخبر المشترين عن معرضك', ku: 'دەربارەی نمایشگاکەت بە کڕیاران بڵێ'),
                            icon: Icons.notes_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: cardFill,
                  shadowColor: Colors.black54,
                  elevation: isLightShell ? 6 : 10,
                  shape: cardShape,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                          icon: Icons.phone_outlined,
                          title: _tr('Contact numbers', ar: 'أرقام التواصل', ku: 'ژمارەکانی پەیوەندی'),
                          subtitle: _tr('Add up to $_editDealerMaxPhones phone numbers.', ar: 'يمكنك إضافة حتى $_editDealerMaxPhones أرقام.', ku: 'دەتوانیت تا $_editDealerMaxPhones ژمارە زیاد بکەیت.'),
                          trailing: OutlinedButton.icon(
                            onPressed: (_saving || _phones.length >= _editDealerMaxPhones)
                                ? null
                                : () => setState(
                                      () => _phones.add(TextEditingController()),
                                    ),
                            style: _outlineAccentStyle(),
                            icon: const Icon(Icons.add),
                            label: Text(_tr('Add', ar: 'إضافة', ku: 'زیادکردن')),
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (var i = 0; i < _phones.length; i++) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _phones[i],
                                  keyboardType: TextInputType.phone,
                                  style: _fieldTextStyle(isLightShell),
                                  decoration: _fieldDecoration(
                                    isLightShell,
                                    label: i == 0
                                        ? _tr('Primary phone', ar: 'الهاتف الأساسي', ku: 'تەلەفۆنی سەرەکی')
                                        : '${_tr('Phone', ar: 'هاتف', ku: 'تەلەفۆن')} ${i + 1}',
                                    icon: Icons.phone_outlined,
                                  ),
                                  validator: i == 0
                                      ? (v) => (v == null || v.trim().isEmpty)
                                          ? _tr('At least one phone is required', ar: 'مطلوب رقم هاتف واحد على الأقل', ku: 'لانیکەم یەک ژمارەی تەلەفۆن پێویستە')
                                          : null
                                      : null,
                                ),
                              ),
                              if (i > 0) ...[
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: IconButton(
                                    tooltip: _tr('Remove', ar: 'إزالة', ku: 'لابردن'),
                                    onPressed: _saving
                                        ? null
                                        : () {
                                            final c = _phones.removeAt(i);
                                            c.dispose();
                                            setState(() {});
                                          },
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (i != _phones.length - 1) const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: cardFill,
                  shadowColor: Colors.black54,
                  elevation: isLightShell ? 6 : 10,
                  shape: cardShape,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: _sectionTitle(
                          icon: Icons.schedule_outlined,
                          title: _tr('Opening hours', ar: 'ساعات العمل', ku: 'کاتەکانی کارکردن'),
                          subtitle: _tr('Start week is Sunday. Tap a day to edit.', ar: 'بداية الأسبوع يوم الأحد. اضغط على يوم للتعديل.', ku: 'دەستپێکی هەفتە یەکشەممەیە. کرتە لە ڕۆژێک بکە بۆ دەستکاری.'),
                        ),
                      ),
                      Divider(height: 1, color: dividerColor),
                      for (var i = 0; i < _editDealerDays.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: dividerColor),
                        Builder(
                          builder: (context) {
                            final d = _editDealerDays[i];
                            final day = _openingHours[d.key]!;
                            return Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
                                key: _openingHoursTileKeys[d.key],
                                controller: _openingHoursTileControllers[d.key],
                                tilePadding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                childrenPadding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                title: Text(
                                  _dayLabel(d.key),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(_daySummaryText(d.key)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: day.enabled,
                                      onChanged: _saving
                                          ? null
                                          : (v) {
                                              setState(() {
                                                day.enabled = v;
                                                if (!v) {
                                                  day.is24h = false;
                                                  day.open = null;
                                                  day.close = null;
                                                  day.legacyText = null;
                                                  _openingHoursTileControllers[d.key]
                                                      ?.collapse();
                                                }
                                              });
                                              if (v) {
                                                _openOpeningHoursDayEditor(d.key);
                                              }
                                            },
                                    ),
                                    const SizedBox(width: 4),
                                    PopupMenuButton<String>(
                                      enabled: !_saving,
                                      onSelected: (value) {
                                        if (value == '24h') {
                                          setState(() {
                                            day.enabled = true;
                                            day.is24h = true;
                                            day.open = null;
                                            day.close = null;
                                            day.legacyText = null;
                                          });
                                        } else if (value == 'clear') {
                                          setState(() {
                                            day.enabled = false;
                                            day.is24h = false;
                                            day.open = null;
                                            day.close = null;
                                            day.legacyText = null;
                                          });
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: '24h',
                                          child: Text(_tr('Set 24 hours', ar: 'تعيين 24 ساعة', ku: 'دانانی 24 کاتژمێر')),
                                        ),
                                        PopupMenuItem(
                                          value: 'clear',
                                          child: Text(_tr('Set closed', ar: 'تعيين مغلق', ku: 'دانانی داخراو')),
                                        ),
                                      ],
                                      child: const Padding(
                                        padding:
                                            EdgeInsets.symmetric(horizontal: 2),
                                        child: Icon(Icons.more_vert),
                                      ),
                                    ),
                                  ],
                                ),
                                children: [
                                  if (!day.enabled)
                                    Text(
                                      _tr('This day is set to closed.', ar: 'هذا اليوم مغلق.', ku: 'ئەم ڕۆژە داخراوە.'),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    )
                                  else if (day.is24h)
                                    Text(
                                      _tr('Open 24 hours.', ar: 'مفتوح 24 ساعة.', ku: '24 کاتژمێر کراوەیە.'),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    )
                                  else
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: _saving
                                                ? null
                                                : () async {
                                                    setState(() {
                                                      day.is24h = false;
                                                      day.legacyText = null;
                                                    });
                                                    final picked =
                                                        await _pickTimeWheel(
                                                      title:
                                                          '${_dayLabel(d.key)} ${_tr('opens at', ar: 'يفتح في', ku: 'دەکرێتەوە لە')}',
                                                      initial: day.open ??
                                                          const TimeOfDay(
                                                            hour: 9,
                                                            minute: 0,
                                                          ),
                                                    );
                                                    if (!mounted ||
                                                        picked == null) {
                                                      return;
                                                    }
                                                    setState(
                                                      () => day.open = picked,
                                                    );
                                                  },
                                            style: _outlineAccentStyle(),
                                            child: Text(
                                              day.open == null
                                                  ? _tr('From', ar: 'من', ku: 'لە')
                                                  : _formatTime(day.open!),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: _saving
                                                ? null
                                                : () async {
                                                    setState(() {
                                                      day.is24h = false;
                                                      day.legacyText = null;
                                                    });
                                                    final picked =
                                                        await _pickTimeWheel(
                                                      title:
                                                          '${_dayLabel(d.key)} ${_tr('closes at', ar: 'يغلق في', ku: 'دادەخرێت لە')}',
                                                      initial: day.close ??
                                                          const TimeOfDay(
                                                            hour: 18,
                                                            minute: 0,
                                                          ),
                                                    );
                                                    if (!mounted ||
                                                        picked == null) {
                                                      return;
                                                    }
                                                    setState(
                                                      () => day.close = picked,
                                                    );
                                                  },
                                            style: _outlineAccentStyle(),
                                            child: Text(
                                              day.close == null
                                                  ? _tr('To', ar: 'إلى', ku: 'بۆ')
                                                  : _formatTime(day.close!),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: cardFill,
                  shadowColor: Colors.black54,
                  elevation: isLightShell ? 6 : 10,
                  shape: cardShape,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                          icon: Icons.map_outlined,
                          title: _tr('Map location', ar: 'موقع الخريطة', ku: 'شوێنی نەخشە'),
                          subtitle: kIsWeb
                              ? _tr('Optional: paste coordinates from Google Maps.', ar: 'اختياري: ألصق الإحداثيات من خرائط Google.', ku: 'ئارەزوومەندانە: کۆئۆردینات لە نەخشەی گووگڵ لێبکەوە.')
                              : _tr('Optional: drop a pin so buyers can open this spot in Google Maps.', ar: 'اختياري: ضع دبوسًا ليتمكن المشترون من فتح هذا الموقع في خرائط Google.', ku: 'ئارەزوومەندانە: پینی شوێن دابنێ بۆ ئەوەی کڕیاران بتوانن ئەم شوێنە لە نەخشەی گووگڵ بکەنەوە.'),
                        ),
                        const SizedBox(height: 12),
                        if (!kIsWeb) ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _saving ? null : _openMapPicker,
                                  style: _outlineAccentStyle(),
                                  icon: const Icon(Icons.map_outlined),
                                  label: Text(
                                    _pickLat != null
                                        ? _tr('Update map pin', ar: 'تحديث دبوس الخريطة', ku: 'نوێکردنەوەی پینی نەخشە')
                                        : _tr('Set map pin', ar: 'تعيين دبوس الخريطة', ku: 'دانانی پینی نەخشە'),
                                  ),
                                ),
                              ),
                              if (_pickLat != null && _pickLng != null) ...[
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: _saving ? null : _clearMapPin,
                                  style: TextButton.styleFrom(
                                    foregroundColor: _editDealerAccent,
                                  ),
                                  child: Text(_tr('Clear', ar: 'مسح', ku: 'پاککردنەوە')),
                                ),
                              ],
                            ],
                          ),
                          Builder(
                            builder: (context) {
                              final pin = _effectivePinForPreview();
                              if (pin == null) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${pin.lat.toStringAsFixed(6)}, ${pin.lng.toStringAsFixed(6)}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 10),
                                    KeyedSubtree(
                                      key: _mapPreviewKey,
                                      child: DealerLocationMapPreview(
                                        latitude: pin.lat,
                                        longitude: pin.lng,
                                        height: 170,
                                        onOpenInGoogleMaps: () =>
                                            _openPinInGoogleMaps(
                                          pin.lat,
                                          pin.lng,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _coordLat,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                                  style: _fieldTextStyle(isLightShell),
                                  decoration: _fieldDecoration(
                                    isLightShell,
                                    label: _tr('Latitude', ar: 'خط العرض', ku: 'لاتیتوود'),
                                    icon: Icons.my_location_outlined,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _coordLng,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                                  style: _fieldTextStyle(isLightShell),
                                  decoration: _fieldDecoration(
                                    isLightShell,
                                    label: _tr('Longitude', ar: 'خط الطول', ku: 'لۆنگیتوود'),
                                    icon: Icons.my_location_outlined,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          Builder(
                            builder: (context) {
                              final pin = _effectivePinForPreview();
                              if (pin == null) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: KeyedSubtree(
                                  key: _mapPreviewKey,
                                  child: DealerLocationMapPreview(
                                    latitude: pin.lat,
                                    longitude: pin.lng,
                                    height: 170,
                                    onOpenInGoogleMaps: () => _openPinInGoogleMaps(
                                      pin.lat,
                                      pin.lng,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
  }
}
