import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../media/media_url.dart';
import 'listing_image_media.dart';
import 'listing_status.dart';

/// Owner-only banner for a PUBLIC listing that has a pending revision (edits
/// waiting for admin review, rejected edits, or edits that were saved but
/// never submitted).
///
/// The listing itself keeps showing its approved content to everyone; this
/// banner is the only place the pending version is surfaced, together with
/// the owner's three possible actions: preview it, keep editing it, or
/// discard it (the live listing is never touched by any of them).
class PendingEditsBanner extends StatelessWidget {
  const PendingEditsBanner({
    super.key,
    required this.listing,
    this.onPreview,
    this.onEdit,
    this.onDiscard,
  });

  final Map<String, dynamic> listing;
  final VoidCallback? onPreview;
  final VoidCallback? onEdit;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    if (!listingHasPendingRevision(listing)) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context)!;
    final rejected = listingHasRejectedEdits(listing);
    final unsubmitted = listingHasUnsubmittedEdits(listing);
    final reason = listingRevisionRejectionReason(listing);

    final String title = rejected
        ? loc.listingBadgeEditsRejected
        : unsubmitted
            ? loc.listingBadgeEditsUnsaved
            : loc.listingBadgeEditsUnderReview;
    final String body = rejected
        ? (reason.isEmpty
            ? loc.listingEditsRejectedNoReason
            : loc.listingEditsRejectedMessage(reason))
        : unsubmitted
            ? loc.listingEditsUnsavedNote
            : loc.listingEditsUnderReviewNote;
    final Color accent = rejected
        ? const Color(0xFFC62828)
        : unsubmitted
            ? const Color(0xFF546E7A)
            : const Color(0xFFF57C00);

    return Container(
      key: const ValueKey('pending_edits_banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (onPreview != null)
                TextButton(
                  key: const ValueKey('pending_edits_preview'),
                  onPressed: onPreview,
                  child: Text(loc.listingPreviewPendingChanges),
                ),
              if (onEdit != null)
                TextButton(
                  key: const ValueKey('pending_edits_edit'),
                  onPressed: onEdit,
                  child: Text(loc.editAction),
                ),
              if (onDiscard != null)
                TextButton(
                  key: const ValueKey('pending_edits_discard'),
                  onPressed: onDiscard,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: Text(loc.listingDiscardPendingEdits),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Read-only preview of the owner's pending version of a listing: the
/// fields that differ from the approved version plus the pending photos
/// (in their pending order, cover first). Nothing here is public.
Future<void> showPendingChangesPreview(
  BuildContext context,
  Map<String, dynamic> listing,
) {
  final working = listingForOwnerEditing(listing);
  final pending = listingPendingRevision(listing);
  final changed = <String>[
    for (final f in (pending?['changed_fields'] as List? ?? const []))
      f.toString(),
  ];
  final images = <String>[];
  final rawImages = working['images'];
  if (rawImages is List) {
    for (final it in rawImages) {
      if (it is! Map) continue;
      if ((it['kind'] ?? 'listing').toString().toLowerCase() == 'damage') {
        continue;
      }
      final src = ListingImageMedia.source(it);
      if (src.isNotEmpty) images.add(resolveListingImageUrl(src));
    }
  }
  final cover = resolveListingImageUrl(
    (working['image_url'] ?? '').toString(),
  );
  if (cover.isNotEmpty) {
    images.remove(cover);
    images.insert(0, cover);
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final loc = AppLocalizations.of(ctx)!;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, controller) => ListView(
          key: const ValueKey('pending_changes_preview'),
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              loc.listingPreviewPendingChanges,
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            if (images.isNotEmpty)
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      images[i],
                      width: 140,
                      height: 110,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 140,
                        height: 110,
                        color: Colors.black12,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            for (final field in changed)
              if (field != 'images' && field != 'videos')
                _PreviewRow(
                  label: field.replaceAll('_', ' '),
                  approved: (listing[field] ?? '').toString(),
                  pending: (working[field] ?? '').toString(),
                ),
          ],
        ),
      );
    },
  );
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.approved,
    required this.pending,
  });

  final String label;
  final String approved;
  final String pending;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Text(
            approved.isEmpty ? '-' : approved,
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ),
          Text(
            pending.isEmpty ? '-' : pending,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
