part of 'edit_dealer_page.dart';

mixin _EditDealerPageBuildBodyUpper on _EditDealerPageSave {
  List<Widget> _editDealerUpperFormCards(BuildContext context) {
    final logoUrl = buildMediaUrl((_currentLogo ?? '').trim());
    final coverUrl = buildMediaUrl((_currentCover ?? '').trim());
    final brightness = Theme.of(context).brightness;
    final cardShape = _pageCardShape(brightness);
    final isLightShell = brightness == Brightness.light;
    final cardFill = isLightShell
        ? Colors.white
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.06),
            AppThemes.darkHomeShellBackground,
          );

    return [
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
    ];
  }
}
