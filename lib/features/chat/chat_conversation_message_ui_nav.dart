part of 'chat_pages.dart';

mixin _ChatConversationMessageUiNav on _ChatConversationComposer {
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
}
