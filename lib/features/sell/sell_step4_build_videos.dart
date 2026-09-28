part of 'sell_flow.dart';

/// CarNet V1 batch-3: ad-hoc localization for the small "already uploaded"
/// label, matching the existing inline en/ar/ku pattern already used by
/// `_showListingMediaLimitSnack` in this feature rather than adding new
/// formal ARB entries for a single short label.
String _alreadyUploadedVideosLabel(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'مقاطع الفيديو المرفوعة بالفعل';
  if (code == 'ku' || code == 'ckb') return 'ڤیدیۆی بارکراوی پێشتر';
  return 'Already uploaded';
}

mixin _SellStep4BuildVideos on _SellStep4BuildDamage {
  List<Widget> _sellStep4BuildVideosSection() {
    final loc = AppLocalizations.of(context)!;
    final hasVideos = _selectedVideos.isNotEmpty;
    // Preview-decoupling fix: the displayed count includes pending
    // server-transcode videos too -- they are just as much a "selected
    // video" from the seller's point of view (previewable/playable right
    // now, counted against the same `_kSellMaxVideos` cap -- see
    // `_pickVideos`) even though they are not in `_selectedVideos` itself.
    final totalVideoCount =
        _selectedVideos.length + _pendingServerTranscodeVideos.length;
    final countLabel = totalVideoCount > 0
        ? loc.addVideoCount(totalVideoCount)
        : loc.tapToSelect;

    return [
      FilterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterSectionHeader(
              title: AppLocalizations.of(context)!.videosOptional,
              valueSummary: countLabel,
            ),
            const SizedBox(height: 12),
            if (_existingServerVideos.isNotEmpty) ...[
              Text(
                _alreadyUploadedVideosLabel(context),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                key: ValueKey(
                  'existing_videos_${_existingServerVideos.map((e) => ListingImageMedia.id(e)).join('|')}',
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.25,
                ),
                itemCount: _existingServerVideos.length,
                itemBuilder: (context, index) {
                  final video = _existingServerVideos[index];
                  final thumbUrl =
                      (video['thumbnail_url'] ?? '').toString().trim();
                  return Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: thumbUrl.isNotEmpty
                            ? _listingNetworkImage(
                                thumbUrl.startsWith('http')
                                    ? thumbUrl
                                    : _buildFullImageUrl(thumbUrl),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              )
                            : Container(
                                color: Colors.grey.shade200,
                                child: Icon(
                                  Icons.videocam,
                                  color: Colors.grey.shade600,
                                  size: 48,
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
                              unawaited(_removeExistingVideoAt(index));
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
              const SizedBox(height: 12),
            ],
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
            // Preview-decoupling fix: videos that local compression
            // determined `requiresServerTranscode` are NEVER added to
            // `_selectedVideos` (that list drives the normal <=100MB
            // multipart upload -- see `sell_listing_media_upload.dart`),
            // but their ORIGINAL local source is still fully previewable/
            // playable right now -- rendered here from
            // `_pendingServerTranscodeVideos` using the EXACT SAME tile
            // pattern (thumbnail + tap-to-play) as the grid above, just
            // sourced from `ServerTranscodeVideoSpec.localSourcePath`
            // instead of a plain `XFile`. Classification only ever
            // affects the SUBMISSION path -- never hides/removes this
            // preview (task requirement 6/7).
            if (_pendingServerTranscodeVideos.isNotEmpty) ...[
              GridView.builder(
                key: ValueKey(
                  'pending_transcode_videos_'
                  '${_pendingServerTranscodeVideos.map((s) => s.draftMediaId).join('|')}',
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.25,
                ),
                itemCount: _pendingServerTranscodeVideos.length,
                itemBuilder: (context, index) {
                  final spec = _pendingServerTranscodeVideos[index];
                  final previewFile = XFile(spec.localSourcePath);
                  return Stack(
                    key: ValueKey('pending_transcode_${spec.draftMediaId}'),
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            AppPageRoute(
                              builder: (_) => ListingPreviewGalleryPage(
                                imageFilesOrUrls: const [],
                                videoFilesOrUrls: <dynamic>[previewFile],
                                initialIndex: 0,
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
                            future: generateVideoThumbnail(previewFile.path),
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
                              _removePendingServerTranscodeVideoAt(index);
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
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isImportingMedia ? null : _pickVideos,
                icon: const Icon(Icons.videocam),
                label: Text(
                  totalVideoCount > 0
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
