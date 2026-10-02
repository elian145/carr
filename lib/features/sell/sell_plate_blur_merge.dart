part of 'sell_flow.dart';

/// Merges per-photo plate-blur results back into their ORIGINAL positions
/// in [originals] -- see `_blurMediaList` (`sell_car_page_plate_blur.dart`).
///
/// Bug this fixes (index-misalignment): `_blurMediaList` only sends the
/// LOCAL-file subset of `originals` to the blur job (already-remote items --
/// e.g. pre-existing edit-mode photos already attached to the listing --
/// are never local files, so `ListingImageMedia.localFile()` filters them
/// out before enqueueing). The blur job's results (`relPaths`) come back
/// ALIGNED WITH THAT FILTERED SUBSET, one entry per local file, in the same
/// order. Naively writing `relPaths[i]` back to `originals[i]` is only
/// correct when EVERY item in `originals` is local (a brand-new listing's
/// first photo batch, with nothing already remote) -- as soon as `originals`
/// mixes remote items with local ones (e.g. editing an existing listing and
/// adding one more photo alongside already-attached photos), `i` walks the
/// FILTERED list's indices while `originals[i]` is read from the
/// UNFILTERED list, silently pairing each blur result with the WRONG
/// original item. This has a direct, user-visible consequence: a remote
/// item at some position gets its `source` overwritten with a blurred
/// output that actually belongs to a *different* photo, and/or the tail of
/// `originals` (remote items beyond `local.length`) is dropped entirely
/// from the returned list.
///
/// [localIndices] must be the index, into [originals], of each entry that
/// was sent to the blur job -- i.e. `originals[localIndices[i]]` is the item
/// whose blur result is `relPaths[i]`. This function returns a list the
/// SAME LENGTH as [originals]: every non-local (remote) position is kept
/// unchanged, and every local position is replaced with the blurred output
/// AT THAT SAME POSITION when the corresponding [relPaths] entry is a
/// non-empty rel path/URL, or left as the original item when it's null/empty
/// (per-photo blur failure -- fail closed to the original, unblurred photo
/// for just that one item, exactly like before this fix).
///
/// [plateBlurApplied], when supplied (aligned 1:1 with [relPaths] -- see
/// `SellImageJobResult.plateBlurApplied`), lets a successful
/// (non-empty-`relPath`) result be tagged truthfully as "not blurred -- no
/// plate detected" (`blur_not_applied: true`) ONLY when the job itself
/// reported no plate was found, distinct from a GENUINE job failure/
/// timeout (empty/null `relPath`), which is now tagged `blur_failed: true`
/// instead -- see `_blurPreviewGrid` (`sell_step_blur_choice_build.dart`)
/// for how each is rendered. Omitting this parameter (every pre-existing
/// caller/test) preserves the exact old behavior: a null/empty `relPath`
/// is tagged `blur_not_applied: true` (the only signal available before
/// `SellImageJobResult` existed).
List<dynamic> mergeBlurResultsIntoOriginals({
  required List<dynamic> originals,
  required List<int> localIndices,
  required List<String?> relPaths,
  List<bool>? plateBlurApplied,
}) {
  final result = List<dynamic>.from(originals);
  final n = localIndices.length < relPaths.length
      ? localIndices.length
      : relPaths.length;
  for (var i = 0; i < n; i++) {
    final idx = localIndices[i];
    if (idx < 0 || idx >= result.length) continue;
    final relPath = relPaths[i];
    final previous = originals[idx];
    if (relPath == null || relPath.isEmpty) {
      if (plateBlurApplied != null) {
        // New, richer call site (`_blurMediaList`): a null/empty relPath
        // here means the job GENUINELY failed (network/timeout/Celery
        // FAILURE/404) -- `SellImageJobResult.failed` -- never "no plate
        // detected" (that case always has a valid `relPath`, see
        // `SellImageJobPolling.awaitImageJobResult`). Tag distinctly so
        // the choice screen shows a truthful failure/retry state instead
        // of the "not blurred -- no plate detected" badge, which would
        // incorrectly imply the job succeeded.
        result[idx] = {
          ...Map<String, dynamic>.from(
            previous is Map
                ? previous.map((k, v) => MapEntry(k.toString(), v))
                : {'source': ListingImageMedia.source(previous)},
          )..remove('blur_pending'),
          'blur_failed': true,
        };
        continue;
      }
      // Pre-existing/legacy call sites (no `plateBlurApplied` supplied):
      // unchanged behavior -- per-photo blur failure/no-plate-detected
      // still falls back to the original bytes at this position, tagged
      // `blur_not_applied: true` exactly as before this fix existed. This
      // has NO effect on final submission correctness: the final upload
      // source is always `original_images` + an explicit `skip_blur` flag
      // (see `SellMediaIdentity.finalListingImages`), never this preview
      // list.
      result[idx] = {
        ...Map<String, dynamic>.from(
          previous is Map
              ? previous.map((k, v) => MapEntry(k.toString(), v))
              : {'source': ListingImageMedia.source(previous)},
        ),
        'blur_not_applied': true,
      };
      continue;
    }

    // THE CORE FIX (real-device evidence: "the Blurred section ALSO
    // visually shows originals, even after selecting Blurred"):
    // `ListingImageMedia.map()` intentionally preserves any existing
    // `preview_source` field on `previous` across unrelated `map()` calls
    // (see its own docstring) -- a locally-generated JPEG preview of a
    // HEIC/HEIF ORIGINAL, consumed by `ListingImageMedia.previewLocalFile()`
    // in PREFERENCE to `source`. Without clearing it here, a blurred
    // entry whose original was HEIC/HEIF keeps pointing
    // `previewLocalFile()` at the stale, UNBLURRED local preview file even
    // though `source` was correctly updated to the real server-processed
    // blurred URL below -- so the blur-choice grid keeps painting the
    // local original forever, regardless of how many times `carData`
    // rebuilds. A blurred result is ALWAYS a freshly server-produced JPEG
    // (never HEIC, see `kk/media_processing.py::normalize_to_canonical_
    // jpeg`), so it must always be rendered via the network URL just set
    // as `source` -- passing `previewSource: ''` explicitly removes any
    // carried-over local preview so `previewLocalFile()` correctly falls
    // through to `localFile()` (which returns `null` for a remote/URL
    // `source`, routing rendering to `_listingNetworkImage`).
    result[idx] = ListingImageMedia.map(
      previous,
      source: relPath,
      focusY: ListingImageMedia.focusY(previous),
      width: ListingImageMedia.width(previous),
      height: ListingImageMedia.height(previous),
      previewSource: '',
    );
    // `ListingImageMedia.map()` only manages its OWN known fields
    // (`source`/`focus_y`/`width`/`height`/`preview_source`) -- it has no
    // concept of `blur_pending`/`blur_failed`/`blur_not_applied` (those are
    // this file's own bookkeeping, layered directly onto the map), so it
    // copies them over from `previous` UNCHANGED, same as any other
    // unrecognized key. `previous` here is very often the
    // `pendingBlurSkeleton` entry this SAME job's own earlier progress
    // publish produced (`blur_pending: true`) -- without explicitly
    // clearing it, a genuinely-resolved, correctly-`source`-updated tile
    // keeps carrying `blur_pending: true` forever, so `_blurPreviewGrid`
    // keeps painting the "Generating blurred preview…" overlay ON TOP of
    // the (now correct) blurred image indefinitely, never visually
    // reaching its terminal state.
    (result[idx] as Map)
      ..remove('blur_pending')
      ..remove('blur_failed');
    final applied = plateBlurApplied != null && i < plateBlurApplied.length
        ? plateBlurApplied[i]
        : true;
    if (!applied) {
      (result[idx] as Map)['blur_not_applied'] = true;
    } else {
      (result[idx] as Map).remove('blur_not_applied');
    }
  }
  return result;
}

/// Builds the "still waiting on its blur job" skeleton for [originals]:
/// every LOCAL position (per [localIndices]) is tagged `blur_pending: true`
/// (unchanged otherwise -- `source` is left as the original, so
/// `previewLocalFile()`/`_listingNetworkImage` keep rendering exactly what
/// the "Original photos" grid already shows for that same item, while
/// `_blurPreviewGrid` -- `sell_step_blur_choice_build.dart` -- additionally
/// paints a "Generating blurred preview…" overlay whenever it sees this
/// flag), every remote position is kept unchanged (nothing to blur/wait
/// on). Written into `carData['blurred_images']`/`blurred_damage_images`
/// via `startBackgroundPlateBlur`'s progress callback the INSTANT the
/// background job starts (before any job id even comes back from the
/// enqueue call), so the blur-choice screen can render a per-tile pending
/// state live instead of one all-or-nothing "still blurring" banner for
/// the whole batch.
List<dynamic> pendingBlurSkeleton({
  required List<dynamic> originals,
  required List<int> localIndices,
}) {
  final result = List<dynamic>.from(originals);
  for (final idx in localIndices) {
    if (idx < 0 || idx >= result.length) continue;
    final previous = originals[idx];
    result[idx] = {
      ...Map<String, dynamic>.from(
        previous is Map
            ? previous.map((k, v) => MapEntry(k.toString(), v))
            : {'source': ListingImageMedia.source(previous)},
      )
        ..remove('blur_not_applied')
        ..remove('blur_failed'),
      'blur_pending': true,
    };
  }
  return result;
}
