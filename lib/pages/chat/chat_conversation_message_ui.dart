part of '../chat_pages.dart';

// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api

extension ChatConversationMessageUi on _ChatConversationPageState {
  void _flashHighlight(String messageId) {
    _highlightTimer?.cancel();
    if (!mounted) return;
    setState(() => _highlightMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _highlightMessageId = null);
    });
  }

  Future<void> _jumpToMessageId(String messageId) async {
    final targetId = messageId.trim();
    if (targetId.isEmpty) return;

    // If the message is older than what we’ve loaded, keep paginating up until we find it.
    var attempts = 0;
    while (_messages.indexWhere((m) => m.id == targetId) == -1 &&
        _hasMoreMessages &&
        !_loadingOlderMessages &&
        attempts < 8) {
      attempts += 1;
      await _loadOlderMessages();
    }

    final index = _messages.indexWhere((m) => m.id == targetId);
    if (index == -1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Original message is not loaded.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!mounted || !_scrollController.hasClients) return;

    // Try to scroll precisely if the target is currently built.
    Future<bool> ensureVisibleIfBuilt() async {
      final key = _messageKeys[targetId];
      final ctx = key?.currentContext;
      if (ctx == null) return false;
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: 0.25,
      );
      _flashHighlight(targetId);
      return true;
    }

    if (await ensureVisibleIfBuilt()) return;

    // Otherwise, scroll close to the item using an estimate, then retry ensureVisible a few times.
    final maxScroll = _scrollController.position.maxScrollExtent;
    final denom = math.max(1, _messages.length - 1);
    final fraction = index / denom;
    final estimatedOffset = (maxScroll * fraction).clamp(0.0, maxScroll);
    await _scrollController.animateTo(
      estimatedOffset,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );

    for (var i = 0; i < 10; i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (!mounted || !_scrollController.hasClients) return;
      if (await ensureVisibleIfBuilt()) return;
    }

    // Fallback: at least show a highlight state when the user scrolls manually.
    _flashHighlight(targetId);
  }

  void _showBlockDialog() {
    final receiverId = widget.receiverId;
    if (receiverId == null || receiverId.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _chatText(
            context,
            'Block User',
            ar: 'حظر المستخدم',
            ku: 'بلۆککردنی بەکارهێنەر',
          ),
        ),
        content: Text(
          _chatText(
            context,
            'Blocked users cannot send you messages and their conversations will be hidden. You can unblock them later.',
            ar: 'المستخدمون المحظورون لا يمكنهم إرسال رسائل إليك وسيتم إخفاء محادثاتهم. يمكنك إلغاء الحظر لاحقاً.',
            ku: 'بەکارهێنەرانێکی بلۆککراو ناتوانن پەیام بۆت بنێرن و گفتوگۆکانیان دەشاردرێنەوە. دەتوانیت دواتر بلۆکەکە هەڵبوەشێنیت.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)?.cancelAction ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ApiService.blockUser(receiverId);
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      _chatText(
                        context,
                        'User blocked',
                        ar: 'تم حظر المستخدم',
                        ku: 'بەکارهێنەر بلۆک کرا',
                      ),
                    ),
                  ),
                );
                Navigator.pop(context);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      userErrorText(
                        context,
                        e,
                        fallback:
                            AppLocalizations.of(context)?.errorTitle ?? 'Error',
                      ),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text(
              _chatText(context, 'Block', ar: 'حظر', ku: 'بلۆک'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    final receiverId = widget.receiverId;
    if (receiverId == null || receiverId.isEmpty) return;
    final reasonController = TextEditingController();
    final detailsController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _chatText(
            context,
            'Report User',
            ar: 'الإبلاغ عن المستخدم',
            ku: 'ڕاپۆرتکردنی بەکارهێنەر',
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'e.g. spam, harassment, scam',
                  border: OutlineInputBorder(),
                ),
                maxLength: 200,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: detailsController,
                decoration: const InputDecoration(
                  labelText: 'Details (optional)',
                  hintText: 'Provide additional details...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                maxLength: 2000,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)?.cancelAction ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _chatText(
                        context,
                        'Please provide a reason',
                        ar: 'يرجى إدخال السبب',
                        ku: 'تکایە هۆکارێک بنووسە',
                      ),
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await ApiService.reportUser(
                  receiverId,
                  reason: reason,
                  details: detailsController.text.trim(),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _chatText(
                        context,
                        'Report submitted. Thank you.',
                        ar: 'تم إرسال البلاغ. شكراً لك.',
                        ku: 'ڕاپۆرتەکە نێردرا. سوپاس.',
                      ),
                    ),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      userErrorText(
                        context,
                        e,
                        fallback:
                            AppLocalizations.of(context)?.errorTitle ?? 'Error',
                      ),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text(
              _chatText(
                context,
                'Submit Report',
                ar: 'إرسال البلاغ',
                ku: 'ناردنی ڕاپۆرت',
              ),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  String _listingTitle(BuildContext context, Map<String, dynamic> car) =>
      localizedListingTitle(context, car);

  String _listingPrice(Map<String, dynamic> car) {
    dynamic raw = car['price'];
    if (raw == null || raw.toString().trim().isEmpty) {
      raw = car['selling_price'] ?? car['amount'] ?? car['formatted_price'];
    }
    final price = (raw ?? '').toString().trim();
    final currency = (car['currency'] ?? car['currency_code'] ?? '')
        .toString()
        .trim();
    if (price.isEmpty) return '';
    return currency.isEmpty ? price : '$price $currency';
  }

  String _listingImageUrl(Map<String, dynamic> car) =>
      listingImageUrlFromMap(car);

  Widget _buildListingCard(BuildContext context, Map<String, dynamic> car) {
    final scheme = Theme.of(context).colorScheme;
    final imageUrl = _listingImageUrl(car);
    final title = _listingTitle(context, car);
    final price = _listingPrice(car);
    final location = (car['location'] ?? car['city'] ?? '').toString().trim();

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.pushNamed(
          context,
          '/car_detail',
            arguments: {'carId': listingPrimaryId(car)},
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).dividerColor
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.55),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: imageUrl.isEmpty
                  ? Container(
                      width: double.infinity,
                      height: 140,
                      color: Colors.black12,
                      child: const Icon(Icons.directions_car),
                    )
                  : Image.network(
                      imageUrl,
                      width: double.infinity,
                      height: 140,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: double.infinity,
                        height: 140,
                        color: Colors.black12,
                        child: const Icon(Icons.directions_car),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              title.isEmpty
                  ? (AppLocalizations.of(context)?.listingTitle ?? 'Listing')
                  : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            if (price.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                price,
                style: const TextStyle(
                  color: _kChatListingCardAccentOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (location.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMediaAttachmentThumbnail(
    BuildContext context,
    ChatAttachment attachment, {
    required double width,
    required double height,
    int? remainingCount,
    VoidCallback? onTap,
  }) {
    Widget child;
    if (attachment.type == 'video') {
      child = Container(
        width: width,
        height: height,
        color: Colors.black87,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.videocam, size: 42, color: Colors.white54),
            Container(
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 26,
              ),
            ),
          ],
        ),
      );
    } else if (attachment.isLocal) {
      child = Image.file(
        File(attachment.url),
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    } else {
      child = Image.network(
        _resolveAttachmentUrl(attachment),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: width,
          height: height,
          color: Colors.black12,
          child: const Icon(Icons.broken_image, size: 36),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (remainingCount != null && remainingCount > 0)
              Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Text(
                  '+$remainingCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceMessageBubble(
    BuildContext context,
    ChatMessage message, {
    required Color iconColor,
    required Color textColor,
    required Color progressColor,
  }) {
    return Stack(
      children: [
        _ChatVoiceBubble(
          message: message,
          iconColor: iconColor,
          textColor: textColor,
          progressColor: progressColor,
        ),
        if (message.isPending)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVoiceRecordingBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
          const SizedBox(width: 8),
          Text(
            _formatVoiceDuration(_voiceRecordDuration),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          TextButton(
            onPressed: _cancelVoiceRecording,
            child: Text(AppLocalizations.of(context)?.cancelAction ?? 'Cancel'),
          ),
          TextButton(
            onPressed: _stopAndSendVoiceRecording,
            child: Text(
              _chatText(context, 'Send', ar: 'إرسال', ku: 'ناردن'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGroupBubble(BuildContext context, ChatMessage message) {
    final attachments = message.attachments;
    final previewCount = attachments.length > 4 ? 4 : attachments.length;

    return GestureDetector(
      onTap: message.isPending ? null : () => _openChatMediaViewer(message),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: previewCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: previewCount == 1 ? 1 : 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: previewCount == 1 ? 1.15 : 1,
              ),
              itemBuilder: (context, index) {
                final remaining =
                    index == previewCount - 1 && attachments.length > 4
                    ? attachments.length - 4
                    : null;
                return _buildMediaAttachmentThumbnail(
                  context,
                  attachments[index],
                  width: double.infinity,
                  height: double.infinity,
                  remainingCount: remaining,
                  onTap: message.isPending
                      ? null
                      : () => _openChatMediaViewer(
                          message,
                          initialAttachmentIndex: index,
                        ),
                );
              },
            ),
          ),
          if (message.isPending)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(strokeWidth: 2),
                      SizedBox(height: 10),
                      Text(
                        'Sending...',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

}
