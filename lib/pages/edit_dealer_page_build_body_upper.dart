part of 'edit_dealer_page.dart';

mixin _EditDealerPageBuildBodyUpper on _EditDealerPageSave {
  Future<void> _confirmRemovePhone(int index) async {
    if (_saving || index <= 0 || index >= _phones.length) return;

    final phoneNumber = _phones[index].text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _tr(
            'Remove phone number?',
            ar: 'إزالة رقم الهاتف؟',
            ku: 'ژمارەی تەلەفۆن لاببرێت؟',
          ),
        ),
        content: Text(
          phoneNumber.isNotEmpty
              ? _tr(
                  'Remove $phoneNumber from your contact numbers?',
                  ar: 'إزالة $phoneNumber من أرقام التواصل؟',
                  ku: '$phoneNumber لە ژمارەکانی پەیوەندیدا لاببرێت؟',
                )
              : _tr(
                  'Remove this phone number from your contact numbers?',
                  ar: 'إزالة رقم الهاتف هذا من أرقام التواصل؟',
                  ku: 'ئەم ژمارەی تەلەفۆنە لە ژمارەکانی پەیوەندیدا لاببرێت؟',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _loc?.cancelAction ??
                  _tr('Cancel', ar: 'إلغاء', ku: 'پاشگەزبوونەوە'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _tr('Remove', ar: 'إزالة', ku: 'لابردن'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final c = _phones.removeAt(index);
    c.dispose();
    setState(() {});
  }

  Future<void> _confirmRemoveEmail(int index) async {
    if (_saving || index < 0 || index >= _emails.length) return;

    final emailAddress = _emails[index].text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _tr(
            'Remove email?',
            ar: 'إزالة البريد الإلكتروني؟',
            ku: 'ئیمەیل لاببرێت؟',
          ),
        ),
        content: Text(
          emailAddress.isNotEmpty
              ? _tr(
                  'Remove $emailAddress from your contact emails?',
                  ar: 'إزالة $emailAddress من رسائل التواصل؟',
                  ku: '$emailAddress لە ئیمەیلەکانی پەیوەندیدا لاببرێت؟',
                )
              : _tr(
                  'Remove this email from your contact emails?',
                  ar: 'إزالة هذا البريد من رسائل التواصل؟',
                  ku: 'ئەم ئیمەیلە لە ئیمەیلەکانی پەیوەندیدا لاببرێت؟',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _loc?.cancelAction ??
                  _tr('Cancel', ar: 'إلغاء', ku: 'پاشگەزبوونەوە'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _tr('Remove', ar: 'إزالة', ku: 'لابردن'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final c = _emails.removeAt(index);
    c.dispose();
    setState(() {});
  }

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
                subtitle: _tr(
                  'Logo and cover image shown on your dealer page.',
                  ar: 'يظهر الشعار وصورة الغلاف في صفحة الوكيل.',
                  ku: 'لۆگۆ و وێنەی کاڤەر لە پەڕەی وەکیلت پیشان دەدرێت.',
                ),
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
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      backgroundImage: _logo != null
                          ? FileImage(File(_logo!.path))
                          : (logoUrl.isNotEmpty
                              ? listingCachedNetworkImageProvider(logoUrl)
                              : null),
                      child: _logo == null && logoUrl.isEmpty
                          ? Icon(
                              Icons.storefront_outlined,
                              size: 26,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
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
                          ? _tr(
                              'Change logo',
                              ar: 'تغيير الشعار',
                              ku: 'گۆڕینی لۆگۆ',
                            )
                          : _tr(
                              'Logo selected',
                              ar: 'تم اختيار الشعار',
                              ku: 'لۆگۆ هەڵبژێردرا',
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _brandingMediaButton(
                      onPressed: _saving ? null : _pickCover,
                      icon: Icons.photo_outlined,
                      selected: _cover != null,
                      label: _cover == null
                          ? _tr(
                              'Change cover',
                              ar: 'تغيير الغلاف',
                              ku: 'گۆڕینی کاڤەر',
                            )
                          : _tr(
                              'Cover selected',
                              ar: 'تم اختيار الغلاف',
                              ku: 'کاڤەر هەڵبژێردرا',
                            ),
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
                title: _tr(
                  'Dealership details',
                  ar: 'تفاصيل المعرض',
                  ku: 'وردەکاری نمایشگا',
                ),
                subtitle: _tr(
                  'What buyers see on your dealer page.',
                  ar: 'ما يراه المشترون في صفحة الوكيل.',
                  ku: 'ئەوەی کڕیاران لە پەڕەی وەکیلت دەیبینن.',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                style: _fieldTextStyle(isLightShell),
                decoration: _fieldDecoration(
                  isLightShell,
                  label: _tr(
                    'Dealership name',
                    ar: 'اسم المعرض',
                    ku: 'ناوی نمایشگا',
                  ),
                  icon: Icons.badge_outlined,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? _tr(
                        'Dealership name is required',
                        ar: 'اسم المعرض مطلوب',
                        ku: 'ناوی نمایشگا پێویستە',
                      )
                    : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _location,
                style: _fieldTextStyle(isLightShell),
                decoration: _fieldDecoration(
                  isLightShell,
                  label: _tr(
                    'Dealership location',
                    ar: 'موقع المعرض',
                    ku: 'شوێنی نمایشگا',
                  ),
                  icon: Icons.location_on_outlined,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? _tr(
                        'Dealership location is required',
                        ar: 'موقع المعرض مطلوب',
                        ku: 'شوێنی نمایشگا پێویستە',
                      )
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
                  hint: _tr(
                    'Tell buyers about your dealership',
                    ar: 'أخبر المشترين عن معرضك',
                    ku: 'دەربارەی نمایشگاکەت بە کڕیاران بڵێ',
                  ),
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
                title: _tr(
                  'Contact numbers',
                  ar: 'أرقام التواصل',
                  ku: 'ژمارەکانی پەیوەندی',
                ),
                subtitle: _tr(
                  'Add up to $_editDealerMaxPhones phone numbers.',
                  ar: 'يمكنك إضافة حتى $_editDealerMaxPhones أرقام.',
                  ku: 'دەتوانیت تا $_editDealerMaxPhones ژمارە زیاد بکەیت.',
                ),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _phones[i],
                      keyboardType: TextInputType.phone,
                      style: _fieldTextStyle(isLightShell),
                      decoration: _fieldDecoration(
                        isLightShell,
                        label: i == 0
                            ? _tr(
                                'Primary phone',
                                ar: 'الهاتف الأساسي',
                                ku: 'تەلەفۆنی سەرەکی',
                              )
                            : '${_tr('Phone', ar: 'هاتف', ku: 'تەلەفۆن')} ${i + 1}',
                        icon: Icons.phone_outlined,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: i == 0
                          ? (v) => (v == null || v.trim().isEmpty)
                                ? _tr(
                                    'At least one phone is required',
                                    ar: 'مطلوب رقم هاتف واحد على الأقل',
                                    ku: 'لانیکەم یەک ژمارەی تەلەفۆن پێویستە',
                                  )
                                : null
                          : null,
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _isDealerPhoneVerified(_phones[i].text)
                              ? null
                              : () => _verifyDealerPhoneAt(i),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            foregroundColor: _editDealerAccent,
                            disabledForegroundColor: Colors.green,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: Icon(
                            _isDealerPhoneVerified(_phones[i].text)
                                ? Icons.verified_rounded
                                : Icons.sms_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _isDealerPhoneVerified(_phones[i].text)
                                ? _tr(
                                    'Verified',
                                    ar: 'موثّق',
                                    ku: 'پشتڕاستکراو',
                                  )
                                : _tr(
                                    'Verify',
                                    ar: 'تحقق',
                                    ku: 'پشتڕاستکردنەوە',
                                  ),
                          ),
                        ),
                        const Spacer(),
                        if (i > 0)
                          IconButton(
                            tooltip: _tr('Remove', ar: 'إزالة', ku: 'لابردن'),
                            onPressed: _saving
                                ? null
                                : () => _confirmRemovePhone(i),
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(
                icon: Icons.email_outlined,
                title: _tr(
                  'Contact emails',
                  ar: 'رسائل التواصل',
                  ku: 'ئیمەیلەکانی پەیوەندی',
                ),
                subtitle: _tr(
                  'Optional. Add up to $_editDealerMaxEmails verified emails.',
                  ar: 'اختياري. يمكنك إضافة حتى $_editDealerMaxEmails بريد موثّق.',
                  ku: 'ئارەزوومەندانە. دەتوانیت تا $_editDealerMaxEmails ئیمەیلی پشتڕاستکراو زیاد بکەیت.',
                ),
                trailing: OutlinedButton.icon(
                  onPressed: (_saving || _emails.length >= _editDealerMaxEmails)
                      ? null
                      : () => setState(
                          () => _emails.add(TextEditingController()),
                        ),
                  style: _outlineAccentStyle(),
                  icon: const Icon(Icons.add),
                  label: Text(_tr('Add', ar: 'إضافة', ku: 'زیادکردن')),
                ),
              ),
              if (_emails.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _tr(
                    'No contact emails yet.',
                    ar: 'لا توجد رسائل تواصل بعد.',
                    ku: 'هێشتا ئیمەیلی پەیوەندی نییە.',
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_emails.isNotEmpty) const SizedBox(height: 12),
              for (var i = 0; i < _emails.length; i++) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _emails[i],
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: _fieldTextStyle(isLightShell),
                      decoration: _fieldDecoration(
                        isLightShell,
                        label:
                            '${_tr('Email', ar: 'البريد', ku: 'ئیمەیل')} ${i + 1}',
                        icon: Icons.email_outlined,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return null;
                        if (!isValidDealerEmailForVerification(value)) {
                          return _tr(
                            'Enter a valid email address',
                            ar: 'أدخل بريداً إلكترونياً صالحاً',
                            ku: 'ئیمەیلێکی دروست بنووسە',
                          );
                        }
                        return null;
                      },
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _isDealerEmailVerified(_emails[i].text)
                              ? null
                              : () => _verifyDealerEmailAt(i),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            foregroundColor: _editDealerAccent,
                            disabledForegroundColor: Colors.green,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: Icon(
                            _isDealerEmailVerified(_emails[i].text)
                                ? Icons.verified_rounded
                                : Icons.mark_email_unread_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _isDealerEmailVerified(_emails[i].text)
                                ? _tr(
                                    'Verified',
                                    ar: 'موثّق',
                                    ku: 'پشتڕاستکراو',
                                  )
                                : _tr(
                                    'Verify',
                                    ar: 'تحقق',
                                    ku: 'پشتڕاستکردنەوە',
                                  ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: _tr('Remove', ar: 'إزالة', ku: 'لابردن'),
                          onPressed: _saving
                              ? null
                              : () => _confirmRemoveEmail(i),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ],
                ),
                if (i != _emails.length - 1) const SizedBox(height: 12),
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(
                icon: Icons.share_outlined,
                title: _tr(
                  'Social media',
                  ar: 'وسائل التواصل',
                  ku: 'تۆڕە کۆمەڵایەتییەکان',
                ),
                subtitle: _tr(
                  'Optional. Enter the username only.',
                  ar: 'اختياري. أدخل اسم المستخدم فقط.',
                  ku: 'ئارەزوومەندانە. تەنها ناوی بەکارهێنەر بنووسە.',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _facebook,
                keyboardType: TextInputType.text,
                autocorrect: false,
                style: _fieldTextStyle(isLightShell),
                decoration: _fieldDecoration(
                  isLightShell,
                  label: _tr(
                    'Facebook username',
                    ar: 'اسم مستخدم فيسبوك',
                    ku: 'ناوی بەکارهێنەری فەیسبووک',
                  ),
                  hint: 'yourpage',
                  icon: Icons.facebook,
                ),
                validator: (v) => _socialFieldError(
                  DealerSocialNetwork.facebook,
                  v,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _instagram,
                keyboardType: TextInputType.text,
                autocorrect: false,
                style: _fieldTextStyle(isLightShell),
                decoration: _fieldDecoration(
                  isLightShell,
                  label: _tr(
                    'Instagram username',
                    ar: 'اسم مستخدم إنستغرام',
                    ku: 'ناوی بەکارهێنەری ئینستاگرام',
                  ),
                  hint: 'username',
                  icon: Icons.camera_alt_outlined,
                  prefixText: '@',
                ),
                validator: (v) => _socialFieldError(
                  DealerSocialNetwork.instagram,
                  v,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tiktok,
                keyboardType: TextInputType.text,
                autocorrect: false,
                style: _fieldTextStyle(isLightShell),
                decoration: _fieldDecoration(
                  isLightShell,
                  label: _tr(
                    'TikTok username',
                    ar: 'اسم مستخدم تيك توك',
                    ku: 'ناوی بەکارهێنەری تیک تۆک',
                  ),
                  hint: 'username',
                  icon: Icons.music_note_outlined,
                  prefixText: '@',
                ),
                validator: (v) => _socialFieldError(
                  DealerSocialNetwork.tiktok,
                  v,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  String? _socialFieldError(DealerSocialNetwork network, String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (DealerSocials.normalize(network, text) == null) {
      return _tr(
        'Enter a valid ${DealerSocials.label(network)} username',
        ar: 'أدخل اسم مستخدم ${DealerSocials.label(network)} صالحاً',
        ku: 'ناوی بەکارهێنەری دروستی ${DealerSocials.label(network)} بنووسە',
      );
    }
    return null;
  }
}
