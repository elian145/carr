part of 'sell_flow.dart';

mixin _SellStep4BuildVideos on _SellStep4BuildDamage {
  List<Widget> _sellStep4BuildVideosSection() {
    final loc = AppLocalizations.of(context)!;
    final hasVideos = _selectedVideos.isNotEmpty;
    final countLabel = hasVideos
        ? loc.addVideoCount(_selectedVideos.length)
        : loc.tapToSelect;

    return [
      FilterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterSectionHeader(
              title: AppLocalizations.of(context)!.videos,
              valueSummary: countLabel,
            ),
            const SizedBox(height: 12),
            if (hasVideos)
              GridView.builder(
                key: ValueKey(_selectedVideos.map((e) => e.path).join('|')),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.25,
                ),
                itemCount: _selectedVideos.length,
                itemBuilder: (context, index) {
                  final video = _selectedVideos[index];
                  return Stack(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            AppPageRoute(
                              builder: (_) => ListingPreviewGalleryPage(
                                imageFilesOrUrls: const [],
                                videoFilesOrUrls:
                                    List<dynamic>.from(_selectedVideos),
                                initialIndex: index,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: FutureBuilder<String?>(
                            future: generateVideoThumbnail(video.path),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data != null) {
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.file(
                                      File(snapshot.data!),
                                      fit: BoxFit.cover,
                                    ),
                                    Center(
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(16),
                                        child: const Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 40,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }
                              return Container(
                                color: Colors.grey.shade200,
                                child: Icon(
                                  Icons.videocam,
                                  color: Colors.grey.shade600,
                                  size: 48,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Semantics(
                          button: true,
                          label: AppLocalizations.of(context)!.removeAction,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedVideos.removeAt(index);
                              });
                              unawaited(_syncMediaDraftToParent());
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(6),
                              child: const Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            if (hasVideos) const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickVideos,
                icon: const Icon(Icons.videocam),
                label: Text(
                  hasVideos
                      ? AppLocalizations.of(context)!.addMoreVideos
                      : AppLocalizations.of(context)!.addVideos,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kFilterAccentColor.withValues(alpha: 0.12),
                  foregroundColor: kFilterAccentColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
