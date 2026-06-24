part of 'chat_pages.dart';

mixin _ChatConversationMessageUi on _ChatConversationMessageUiNav {
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

  double _measureLineTextWidth(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final normalized = text.trim();
    if (normalized.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: normalized, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width.ceilToDouble();
  }

  double _measureMultilineMaxLineWidth(
    BuildContext context,
    String text,
    TextStyle style,
    double maxWidth,
  ) {
    final normalized = text.trim();
    if (normalized.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: normalized, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    var widest = 0.0;
    for (final line in painter.computeLineMetrics()) {
      widest = math.max(widest, line.width);
    }
    final width = widest > 0 ? widest : painter.width;
    return width.ceilToDouble();
  }

  double _bubbleBorderInset({
    required bool isMe,
    required bool isHighlighted,
  }) {
    if (isHighlighted) return 4;
    if (!isMe) return 2;
    return 0;
  }

  double _shrinkWrapBubbleInnerWidth(
    BuildContext context, {
    required ChatMessage message,
    required double maxInnerWidth,
    required bool isMe,
    required bool isHighlighted,
    required Color bubbleOnStrong,
    required Color bubbleOnMuted,
  }) {
    final bodyStyle = DefaultTextStyle.of(context).style.copyWith(
      color: bubbleOnStrong,
      fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
    );
    final metaStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: bubbleOnMuted,
          fontSize: 12,
        ) ??
        TextStyle(color: bubbleOnMuted, fontSize: 12);

    final bodyWidth = _measureMultilineMaxLineWidth(
      context,
      _chatDisplayContent(context, message),
      bodyStyle,
      maxInnerWidth,
    );

    var metaLeftWidth = _measureLineTextWidth(
      context,
      _relativeTime(context, message.createdAt),
      metaStyle,
    );
    if (message.editedAt != null && !message.isDeleted) {
      metaLeftWidth +=
          6 + _measureLineTextWidth(context, _chatEditedLabel(context), metaStyle);
    }

    final contentWidth = !isMe
        ? math.max(bodyWidth, metaLeftWidth)
        : math.max(
            bodyWidth,
            metaLeftWidth + _kOutgoingMetaMinGap + 18,
          );
    return contentWidth + _bubbleBorderInset(isMe: isMe, isHighlighted: isHighlighted);
  }

  Widget _buildMessageStatusIndicator(
    BuildContext context,
    ChatMessage message,
  ) {
    final color = message.isRead ? Colors.lightBlueAccent : Colors.white70;
    if (message.isPending) {
      return const Icon(Icons.schedule, size: 14, color: Colors.white70);
    }
    return Icon(
      message.isRead ? Icons.done_all : Icons.check,
      size: 16,
      color: color,
    );
  }
}
