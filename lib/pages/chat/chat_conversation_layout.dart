part of '../chat_pages.dart';

// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api

const double _kOutgoingMetaMinGap = 14;
const double _kBubbleHorizontalPadding = 32;

extension ChatConversationLayout on _ChatConversationPageState {
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
