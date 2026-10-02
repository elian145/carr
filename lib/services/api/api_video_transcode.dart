part of '../api_service.dart';

/// Phase 3B: Flutter client for the resumable server-side video transcode
/// fallback (`kk/routes/media.py`'s `sign-video-source-upload` /
/// `finalize-video-source-upload` / `attach-transcoded-video`). Mirrors the
/// EXISTING `signR2ImageUpload()` / `uploadToSignedUpload()` direct-to-R2
/// convention in `api_listings.dart`, except the upload itself is
/// STREAMED (never reads the whole -- up to 500MiB -- source file into
/// memory) so it can report real byte-level progress.
abstract final class _ApiServiceVideoTranscode {
  _ApiServiceVideoTranscode._();

  /// `POST /api/media/r2/sign-video-source-upload`.
  ///
  /// [contentLength] and [contentType] are cryptographically bound into
  /// the presigned URL's signature (same contract as
  /// `signR2ImageUpload`) -- the PUT below must send EXACTLY these.
  ///
  /// Throws [ApiException] with `statusCode == 404` when the server
  /// feature flag (`VIDEO_SOURCE_STAGING_ENABLED`) is off -- callers must
  /// treat that as permanent-for-now ("can't be processed on this
  /// device"), never retry forever, and never fall back to any other
  /// upload path for this video.
  static Future<Map<String, dynamic>> signVideoSourceUpload({
    required String draftMediaId,
    required int contentLength,
    required String contentType,
    String? filename,
  }) async {
    final body = <String, dynamic>{
      'draft_media_id': draftMediaId,
      'content_length': contentLength,
      'content_type': contentType,
      if (filename != null && filename.isNotEmpty) 'filename': filename,
    };
    return await ApiService._makeAuthenticatedRequest(
      'POST',
      '/media/r2/sign-video-source-upload',
      body: body,
    );
  }

  /// Streams [localPath]'s bytes to [uploadUrl] via a single PUT, never
  /// buffering the whole file in memory. [contentLength]/[contentType]
  /// must be EXACTLY what was passed to [signVideoSourceUpload] -- R2
  /// rejects a PUT whose actual bytes/declared type don't match what was
  /// signed. [onProgress] (best-effort, bytes sent so far / total) is
  /// invoked from the read loop -- safe to drive a UI progress bar
  /// directly (already on whichever isolate `await`ed this).
  ///
  /// A long-lived timeout (default 10 minutes) is used instead of the
  /// short warm/cold JSON timeouts elsewhere in this file -- this is a
  /// large binary PUT direct to R2, not a small JSON round-trip through
  /// Flask.
  static Future<void> uploadVideoSourceToR2({
    required String uploadUrl,
    required String localPath,
    required int contentLength,
    required String contentType,
    void Function(int sent, int total)? onProgress,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final file = File(localPath);
    final uri = Uri.parse(uploadUrl);
    final request = http.StreamedRequest('PUT', uri)
      ..headers['Content-Type'] = contentType
      ..contentLength = contentLength;

    var sent = 0;
    Object? readError;
    unawaited(
      () async {
        try {
          await for (final chunk in file.openRead()) {
            request.sink.add(chunk);
            sent += chunk.length;
            onProgress?.call(sent, contentLength);
          }
          await request.sink.close();
        } catch (e) {
          readError = e;
          try {
            request.sink.addError(e);
          } catch (_) {
            // Sink may already be closed/errored -- the outer catch in
            // `send()` below still surfaces `readError`.
          }
        }
      }(),
    );

    final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await ApiService._httpClient
          .send(request)
          .timeout(timeout);
    } catch (e) {
      // A local file-read failure surfaces here as the send() failing
      // too (the sink errored) -- prefer that original error when known,
      // since "R2 PUT failed" alone would be misleading for a genuinely
      // local (not network) cause.
      if (readError != null) throw readError!;
      rethrow;
    }
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        message: response.body.isNotEmpty
            ? response.body
            : 'Video source upload failed',
      );
    }
  }

  /// `POST /api/media/r2/finalize-video-source-upload`.
  ///
  /// Safe to call repeatedly for the SAME [draftMediaId] (see the
  /// backend's own idempotent-enqueue docstring): a repeated call after a
  /// lost response reuses/returns the SAME `task_id` rather than
  /// enqueueing a duplicate transcode job.
  ///
  /// Throws [ApiException] with `statusCode == 404` when the feature flag
  /// is off, or when the staged object genuinely cannot be found yet
  /// (upload not actually finished) -- callers must distinguish these via
  /// the response `message`, not assume either meaning from the code
  /// alone if avoidable; in practice the caller only ever calls this
  /// AFTER a confirmed-successful PUT, so a 404 here almost always means
  /// feature-disabled or an R2 propagation delay worth a bounded retry.
  static Future<Map<String, dynamic>> finalizeVideoSourceUpload({
    required String draftMediaId,
    String? stagingKey,

    /// Media-readiness: when the destination car already exists (i.e.
    /// this draft is being finalized as part of a `submitFast()` run
    /// against an already-created car, not a pre-create draft upload),
    /// pass its id so the backend can advance the matching
    /// `CarMediaItem` manifest row (registered via `expected_media` at
    /// `create_car()` time) to Phase-A-accepted and, later, self-attach
    /// the finished transcode with zero further client calls. Omitted /
    /// unresolved car ids are fully backwards compatible -- the backend
    /// just has no manifest row to advance.
    String? carId,
  }) async {
    final body = <String, dynamic>{
      'draft_media_id': draftMediaId,
      if (stagingKey != null && stagingKey.isNotEmpty)
        'staging_key': stagingKey,
      if (carId != null && carId.trim().isNotEmpty) 'car_id': carId.trim(),
    };
    return await ApiService._makeAuthenticatedRequest(
      'POST',
      '/media/r2/finalize-video-source-upload',
      body: body,
    );
  }

  /// `POST /api/media/r2/attach-transcoded-video`.
  ///
  /// Idempotent (see the backend's own docstring): a repeated call for
  /// the same `(car_id, draft_media_id)` -- with ANY `task_id`, even a
  /// stale one -- returns the SAME already-attached `CarVideo` instead of
  /// creating a duplicate. Safe to call again after a lost response.
  static Future<Map<String, dynamic>> attachTranscodedVideo({
    required String carId,
    required String draftMediaId,
    required String taskId,
  }) async {
    final body = <String, dynamic>{
      'car_id': carId,
      'draft_media_id': draftMediaId,
      'task_id': taskId,
    };
    return await ApiService._makeAuthenticatedRequest(
      'POST',
      '/media/r2/attach-transcoded-video',
      body: body,
    );
  }
}
