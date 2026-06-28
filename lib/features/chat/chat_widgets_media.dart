part of 'chat_pages.dart';

class _ChatMediaEntry {
  final ChatAttachment attachment;
  final String senderName;

  const _ChatMediaEntry({required this.attachment, required this.senderName});
}

void _showChatMediaDialog(
  BuildContext context,
  List<_ChatMediaEntry> entries, {
  int initialIndex = 0,
}) {
  Navigator.of(context).push(
    AppPageRoute<void>(
      builder: (_) =>
          _ChatMediaGroupViewer(entries: entries, initialIndex: initialIndex),
    ),
  );
}

class _ChatMediaGroupViewer extends StatefulWidget {
  final List<_ChatMediaEntry> entries;
  final int initialIndex;

  const _ChatMediaGroupViewer({required this.entries, this.initialIndex = 0});

  @override
  State<_ChatMediaGroupViewer> createState() => _ChatMediaGroupViewerState();
}

class _ChatMediaGroupViewerState extends State<_ChatMediaGroupViewer> {
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
                      videoUrl: _resolveAttachmentUrl(attachment),
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
                          : Image.network(
                              _resolveAttachmentUrl(attachment),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
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
