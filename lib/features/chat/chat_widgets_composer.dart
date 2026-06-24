part of 'chat_pages.dart';

Widget buildChatReplyPreviewCard(
  BuildContext context,
  ChatReplyPreview reply, {
  required bool isMe,
  bool dense = false,
  VoidCallback? onTap,
}) {
  final theme = Theme.of(context);
  final baseColor = isMe
      ? Colors.white.withValues(alpha: 0.14)
      : _homeListingCardBackgroundFill(context);
  final borderColor = isMe
      ? Colors.white.withValues(alpha: 0.5)
      : Colors.white.withValues(alpha: 0.12);
  final inner = Container(
    width: double.infinity,
    margin: EdgeInsets.only(bottom: dense ? 6 : 8),
    padding: EdgeInsets.symmetric(
      horizontal: dense ? 8 : 10,
      vertical: dense ? 6 : 8,
    ),
    decoration: BoxDecoration(
      color: baseColor,
      borderRadius: BorderRadius.circular(12),
      border: Border(left: BorderSide(color: borderColor, width: 3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          (reply.senderName ?? 'Message').trim().isNotEmpty
              ? reply.senderName!.trim()
              : 'Message',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          reply.content.trim().isEmpty ? 'Message' : reply.content.trim(),
          maxLines: dense ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white70,
          ),
        ),
      ],
    ),
  );

  if (onTap == null) return inner;

  return Material(
    type: MaterialType.transparency,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: inner,
    ),
  );
}

Widget buildChatComposerActionBanner(
  BuildContext context, {
  required bool isEditMode,
  required ChatReplyPreview replyPreview,
  required VoidCallback onCancel,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEditMode
                    ? _chatText(
                        context,
                        'Editing message',
                        ar: 'تعديل الرسالة',
                        ku: 'دەستکاریکردنی پەیام',
                      )
                    : _chatText(
                        context,
                        'Replying to message',
                        ar: 'الرد على الرسالة',
                        ku: 'وەڵامدانەوەی پەیام',
                      ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              buildChatReplyPreviewCard(
                context,
                replyPreview,
                isMe: false,
                dense: true,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onCancel,
          icon: const Icon(Icons.close),
          tooltip: AppLocalizations.of(context)?.cancelAction ?? 'Cancel',
        ),
      ],
    ),
  );
}

Widget _buildChatComposerAttachmentTile({
  required BuildContext context,
  required Widget child,
  required VoidCallback onRemove,
}) {
  return Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 72,
          height: 72,
          color: Theme.of(context).cardColor,
          child: child,
        ),
      ),
      Positioned(
        top: 4,
        right: 4,
        child: InkWell(
          onTap: onRemove,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(4),
            child: const Icon(Icons.close, size: 14, color: Colors.white),
          ),
        ),
      ),
    ],
  );
}

Widget _buildChatHorizontalAttachmentScroller({
  required int itemCount,
  required Widget Function(BuildContext context, int index) itemBuilder,
}) {
  if (itemCount == 0) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: itemBuilder,
      ),
    ),
  );
}

Widget buildChatDraftAttachmentsPreview(
  BuildContext context, {
  required List<XFile> files,
  required bool Function(XFile file) isVideoFile,
  required void Function(int index) onRemoveAt,
}) {
  return _buildChatHorizontalAttachmentScroller(
    itemCount: files.length,
    itemBuilder: (context, index) {
      final file = files[index];
      final isVideo = isVideoFile(file);
      final path = file.path;
      return _buildChatComposerAttachmentTile(
        context: context,
        onRemove: () => onRemoveAt(index),
        child: isVideo
            ? const Center(child: Icon(Icons.videocam, size: 28))
            : Image.file(
                File(path),
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
      );
    },
  );
}

Widget buildChatEditingAttachmentsPreview(
  BuildContext context, {
  required List<ChatAttachment> attachments,
  required void Function(int index) onRemoveAt,
}) {
  return _buildChatHorizontalAttachmentScroller(
    itemCount: attachments.length,
    itemBuilder: (context, index) {
      final attachment = attachments[index];
      final isVideo = attachment.type.toLowerCase() == 'video';
      final resolved = buildMediaUrl(attachment.url);
      return _buildChatComposerAttachmentTile(
        context: context,
        onRemove: () => onRemoveAt(index),
        child: isVideo
            ? const Center(child: Icon(Icons.videocam, size: 28))
            : Image.network(
                resolved,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
      );
    },
  );
}
