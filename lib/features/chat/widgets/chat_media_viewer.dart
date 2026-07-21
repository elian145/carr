import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/widgets/listing_network_image.dart';
import '../../../l10n/app_localizations.dart';
import '../../../navigation/app_page_route.dart';
import '../../../services/websocket_service.dart';
import '../../../shared/media/media_url.dart';
import '../../../widgets/in_app_video_screen.dart';

class ChatMediaEntry {
  final ChatAttachment attachment;
  final String senderName;

  const ChatMediaEntry({required this.attachment, required this.senderName});
}

String resolveChatAttachmentUrl(ChatAttachment attachment) {
  if (attachment.isLocal) return attachment.url;
  return buildMediaUrl(attachment.url);
}

void showChatMediaDialog(
  BuildContext context,
  List<ChatMediaEntry> entries, {
  int initialIndex = 0,
}) {
  Navigator.of(context).push(
    AppPageRoute<void>(
      builder: (_) =>
          ChatMediaGroupViewer(entries: entries, initialIndex: initialIndex),
    ),
  );
}

class ChatMediaGroupViewer extends StatefulWidget {
  final List<ChatMediaEntry> entries;
  final int initialIndex;

  const ChatMediaGroupViewer({
    super.key,
    required this.entries,
    this.initialIndex = 0,
  });

  @override
  State<ChatMediaGroupViewer> createState() => _ChatMediaGroupViewerState();
}

class _ChatMediaGroupViewerState extends State<ChatMediaGroupViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.entries.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.entries.length,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemBuilder: (context, index) {
                  final entry = widget.entries[index];
                  final attachment = entry.attachment;
                  if (attachment.type == 'video') {
                    return GalleryEmbeddedVideoPlayer(
                      videoUrl: resolveChatAttachmentUrl(attachment),
                      isActive: index == _currentIndex,
                    );
                  }
                  return Center(
                    child: InteractiveViewer(
                      child: attachment.isLocal
                          ? Image.file(
                              File(attachment.url),
                              fit: BoxFit.contain,
                            )
                          : listingNetworkImage(
                              resolveChatAttachmentUrl(attachment),
                              fit: BoxFit.contain,
                              errorWidget: const Icon(
                                Icons.broken_image,
                                color: Colors.white,
                                size: 64,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 12,
              left: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    '${_currentIndex + 1}/${widget.entries.length}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 72,
              right: 56,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    widget.entries[_currentIndex].senderName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: AppLocalizations.of(context)?.close ?? 'Close',
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
