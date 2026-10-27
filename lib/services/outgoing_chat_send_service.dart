import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:image_picker/image_picker.dart';

import '../shared/debug/app_log.dart';
import '../shared/debug/expected_client_noise.dart';
import '../shared/prefs/chat_pending_send_prefs.dart';
import 'api_service.dart';
import 'connectivity_service.dart';

/// BE-18: one key per logical send attempt (one call to a `start*Send`
/// method below), reused for every automatic transport-level retry of that
/// same HTTP request (timeout retry in `_sendWithAdaptiveTimeout`, 401
/// token-refresh retry) because it is generated once here and then baked
/// into the `Idempotency-Key` header for the entire lifetime of that single
/// `ApiService.sendChatXxx(...)` call. A brand-new user action (pressing
/// Send again after a failure, recording a new voice note, picking new
/// photos) always calls `start*Send` again, which generates a fresh key —
/// so distinct messages never share a key.
///
/// F-11: the SAME key is also reused for every *durable* retry of that
/// logical send performed by [OutgoingChatSendService.recoverPendingSends]
/// (after connectivity returns, the chat is reopened, or the app
/// restarts) — see [ChatPendingSendRecord.idempotencyKey]. A durable retry
/// never calls [_newChatIdempotencyKey] again; it replays the persisted key.
///
/// No `uuid` package dependency is added for this: `uuid` is only a
/// transitive dependency today (not declared in pubspec.yaml), and a
/// microsecond timestamp plus a cryptographically-irrelevant random suffix
/// is already unique enough for a short-TTL, per-actor-scoped idempotency
/// key (see kk/idempotency.py).
final Random _idemKeyRandom = Random();

String _newChatIdempotencyKey() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final rnd = _idemKeyRandom.nextInt(0x7fffffff);
  return 'chat-send-$ts-$rnd';
}

String _newTempMessageId() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final rnd = _idemKeyRandom.nextInt(0x7fffffff);
  return 'temp-$ts-$rnd';
}

/// F-11: classifies a chat-send failure as safe to retry automatically
/// (transient network/transport trouble) vs. a definitive failure the user
/// must act on (validation, permission, auth). Mirrors the equivalent
/// classification already used for listing-media upload retries
/// (`SellListingMediaUpload._isTransientUploadError`) so the same notion of
/// "transient" is used consistently across the app.
bool isRetryableChatSendError(Object error) {
  if (error is TimeoutException) return true;
  if (error is ApiException) {
    final code = error.statusCode;
    return code == 408 ||
        code == 429 ||
        code == 500 ||
        code == 502 ||
        code == 503 ||
        code == 504;
  }
  return isTransientNetworkError(error);
}

enum OutgoingChatSendKind { mediaGroup, textMessage, audio }

String _kindToStorageString(OutgoingChatSendKind kind) {
  switch (kind) {
    case OutgoingChatSendKind.mediaGroup:
      return 'mediaGroup';
    case OutgoingChatSendKind.textMessage:
      return 'text';
    case OutgoingChatSendKind.audio:
      return 'audio';
  }
}

OutgoingChatSendKind? _kindFromStorageString(String s) {
  switch (s) {
    case 'mediaGroup':
      return OutgoingChatSendKind.mediaGroup;
    case 'text':
      return OutgoingChatSendKind.textMessage;
    case 'audio':
      return OutgoingChatSendKind.audio;
  }
  return null;
}

/// Snapshot of a media upload still in progress (survives leaving the chat screen).
class InFlightMediaSend {
  InFlightMediaSend({
    required this.ownerUserId,
    required this.conversationId,
    required this.tempMessageId,
    required this.files,
    required this.startedAt,
    this.receiverId,
    this.carId,
    this.replyToMessageId,
    this.replyToPreviewJson,
    this.listingPreview,
  });

  /// Verified account that started this upload (F-34/F-35). Never shown to,
  /// or retried by, any other account.
  final String? ownerUserId;
  final String conversationId;
  final String tempMessageId;
  final List<XFile> files;
  final DateTime startedAt;
  final String? receiverId;
  final String? carId;
  final String? replyToMessageId;
  final Map<String, dynamic>? replyToPreviewJson;
  final Map<String, dynamic>? listingPreview;
}

class OutgoingChatSendEvent {
  OutgoingChatSendEvent({
    required this.kind,
    required this.ownerUserId,
    required this.conversationId,
    required this.success,
    this.tempMessageId,
    this.messageJson,
    this.error,
    this.errorCause,
    this.restoreFiles,
    this.restoreCaption,
    this.restoredPlainText,
    this.pendingRetry = false,
  });

  final OutgoingChatSendKind kind;

  /// Account that owns the send this event reports on. Events are broadcast
  /// globally, so every consumer MUST ignore events whose owner is not the
  /// currently signed-in account (F-35): conversation ids alone are not an
  /// ownership boundary.
  final String? ownerUserId;
  final String conversationId;
  final bool success;
  final String? tempMessageId;
  final Map<String, dynamic>? messageJson;
  final String? error;
  /// Original failure cause when available (prefer for [userErrorText]).
  final Object? errorCause;
  final List<XFile>? restoreFiles;
  final String? restoreCaption;
  final String? restoredPlainText;

  /// F-11: true when this failure was classified as retryable and a durable
  /// pending record was persisted for automatic background retry — the UI
  /// should keep the pending bubble (not restore content to the composer,
  /// not show a definitive "Send failed" error) since a retry is expected.
  final bool pendingRetry;
}

/// Fire-and-forget chat sends so uploads continue if the user leaves the screen.
/// Results are delivered on [events] (best-effort while a listener is active).
///
/// F-11: on a retryable (transient network/transport) failure, the logical
/// send is additionally persisted via [ChatPendingSendPrefs] so it survives
/// leaving the conversation, backgrounding, or killing the app, and can be
/// retried later — via [recoverPendingSends] — reusing the exact same
/// idempotency key. Non-retryable (definitive) failures are not persisted;
/// they keep the pre-existing behavior of restoring content to the composer
/// for a manual resend.
class OutgoingChatSendService {
  OutgoingChatSendService._();
  static final OutgoingChatSendService instance = OutgoingChatSendService._();

  /// Bounded automatic-retry budget (F-11 requirement: no infinite retry
  /// loop). Once exhausted, the record stays persisted/visible but is only
  /// retried again via an explicit user action (recall-to-composer, which
  /// discards the record and starts a brand-new logical send).
  static const int maxAutoRetryAttempts = 5;

  /// Minimum spacing between automatic retry attempts of the *same*
  /// pending send, so overlapping recovery triggers (app start, chat open,
  /// connectivity change happening close together) cannot spin the same
  /// send repeatedly in a tight loop.
  static const Duration minAutoRetryInterval = Duration(seconds: 20);

  final StreamController<OutgoingChatSendEvent> _controller =
      StreamController<OutgoingChatSendEvent>.broadcast();

  Stream<OutgoingChatSendEvent> get events => _controller.stream;

  final Map<String, InFlightMediaSend> _inFlightMediaByTempId = {};

  /// Ids currently being (re)sent by [recoverPendingSends]/[_retryPersistedRecord],
  /// so a second recovery trigger firing before the first one settles cannot
  /// start a duplicate concurrent attempt for the same logical send.
  final Set<String> _retryInProgressIds = <String>{};

  bool _recoveryScanRunning = false;
  bool _connectivityHooked = false;

  /// Active media uploads keyed by temp message id.
  ///
  /// Only the signed-in account's uploads are visible: another account's
  /// in-flight upload for the same conversation id is never returned.
  List<InFlightMediaSend> inFlightMediaForConversation(
    String conversationId, {
    required String? ownerUserId,
  }) {
    if (ownerUserId == null || ownerUserId.isEmpty) {
      return const <InFlightMediaSend>[];
    }
    return _inFlightMediaByTempId.values
        .where(
          (e) =>
              e.conversationId == conversationId &&
              e.ownerUserId == ownerUserId,
        )
        .toList(growable: false);
  }

  /// Throws [ApiSessionChangedException] unless [session] is still the live
  /// session of the same verified account. Called immediately before a send
  /// is dispatched so a send begun under A can never go out under B (or under
  /// a later login of A that has not been re-validated).
  void _assertSessionStillOwner(AuthSessionSnapshot session) {
    if (session.accountId == null ||
        !ApiService.isSessionCurrent(session) ||
        ApiService.currentAccountId != session.accountId) {
      throw ApiSessionChangedException();
    }
  }

  /// Snapshot for a new send, or null when sending is not allowed: signed out,
  /// identity unverified, or [expectedOwnerUserId] (the account the UI was
  /// opened for) is no longer the signed-in account.
  AuthSessionSnapshot? _sessionForNewSend(String? expectedOwnerUserId) {
    final session = ApiService.captureSession();
    final owner = session.accountId;
    if (!session.authenticated || owner == null) return null;
    if (expectedOwnerUserId != null && expectedOwnerUserId != owner) {
      return null;
    }
    return session;
  }

  /// Stop tracking an upload (user discarded / recalled); the HTTP call may still finish.
  ///
  /// Kept for any existing caller; [discardPendingSend] is the F-11 superset
  /// that also clears a durable pending-retry record and should be
  /// preferred by new call sites.
  void discardInFlightMedia(String tempMessageId) {
    _inFlightMediaByTempId.remove(tempMessageId);
  }

  /// F-11: stop tracking an outgoing send entirely — both the in-memory
  /// in-flight bookkeeping (media/audio) and any durable pending-retry
  /// record (any kind). The underlying HTTP call, if one is still in
  /// flight, may still finish; the UI's own discarded-id tracking
  /// (`_discardedOutgoingIds`) is responsible for ignoring a late result.
  /// Safe to call for an id with no pending record.
  void discardPendingSend(String tempMessageId) {
    _inFlightMediaByTempId.remove(tempMessageId);
    _retryInProgressIds.remove(tempMessageId);
    unawaited(ChatPendingSendPrefs.remove(tempMessageId));
  }

  void _emit(OutgoingChatSendEvent e) {
    if (!_controller.isClosed) {
      _controller.add(e);
    }
  }

  /// F-11: begin listening for connectivity coming back online and retry
  /// any durable pending sends when it does. Safe to call more than once
  /// (only hooks once). Intended to be called once during app bootstrap,
  /// mirroring `SellPendingMediaResume`'s own startup hook.
  void hookConnectivityRecovery() {
    if (_connectivityHooked) return;
    _connectivityHooked = true;
    var wasOnline = ConnectivityService.instance.isOnline.value;
    ConnectivityService.instance.isOnline.addListener(() {
      final isOnline = ConnectivityService.instance.isOnline.value;
      if (isOnline && !wasOnline) {
        unawaited(recoverPendingSends());
      }
      wasOnline = isOnline;
    });
  }

  void startMediaGroupSend({
    required String conversationId,
    required List<XFile> files,
    required String tempMessageId,
    required DateTime startedAt,
    String? receiverId,
    String? carId,
    String? caption,
    String? replyToMessageId,
    Map<String, dynamic>? replyToPreviewJson,
    Map<String, dynamic>? listingPreview,
    required List<XFile> restoreFiles,
    String? restoreCaption,
    String? expectedOwnerUserId,
  }) {
    final session = _sessionForNewSend(expectedOwnerUserId);
    if (session == null) {
      _emit(OutgoingChatSendEvent(
        kind: OutgoingChatSendKind.mediaGroup,
        ownerUserId: expectedOwnerUserId ?? ApiService.currentAccountId,
        conversationId: conversationId,
        success: false,
        tempMessageId: tempMessageId,
        errorCause: ApiSessionChangedException(),
        restoreFiles: restoreFiles,
        restoreCaption: restoreCaption,
      ));
      return;
    }
    _inFlightMediaByTempId[tempMessageId] = InFlightMediaSend(
      ownerUserId: session.accountId,
      conversationId: conversationId,
      tempMessageId: tempMessageId,
      files: List<XFile>.from(files),
      startedAt: startedAt,
      receiverId: receiverId,
      carId: carId,
      replyToMessageId: replyToMessageId,
      replyToPreviewJson: replyToPreviewJson,
      listingPreview: listingPreview,
    );
    final idempotencyKey = _newChatIdempotencyKey();
    unawaited(_runMediaGroupSend(
      conversationId: conversationId,
      files: files,
      tempMessageId: tempMessageId,
      idempotencyKey: idempotencyKey,
      receiverId: receiverId,
      caption: caption,
      replyToMessageId: replyToMessageId,
      replyToPreviewJson: replyToPreviewJson,
      listingPreview: listingPreview,
      restoreFiles: restoreFiles,
      restoreCaption: restoreCaption,
      createdAt: startedAt,
      attemptNumber: 1,
      session: session,
    ));
  }

  Future<void> _runMediaGroupSend({
    required String conversationId,
    required List<XFile> files,
    required String tempMessageId,
    required String idempotencyKey,
    String? receiverId,
    String? caption,
    String? replyToMessageId,
    Map<String, dynamic>? replyToPreviewJson,
    Map<String, dynamic>? listingPreview,
    required List<XFile> restoreFiles,
    String? restoreCaption,
    required DateTime createdAt,
    required int attemptNumber,
    required AuthSessionSnapshot session,
  }) async {
    final ownerUserId = session.accountId;
    try {
      _assertSessionStillOwner(session);
      final response = await ApiService.sendChatMediaGroup(
        conversationId: conversationId,
        files: files,
        receiverId: receiverId,
        caption: caption,
        replyToMessageId: replyToMessageId,
        listingPreview: listingPreview,
        idempotencyKey: idempotencyKey,
      );
      final msg = response['message'];
      if (msg is Map<String, dynamic>) {
        await ChatPendingSendPrefs.remove(tempMessageId);
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.mediaGroup,
          ownerUserId: ownerUserId,
          conversationId: conversationId,
          success: true,
          tempMessageId: tempMessageId,
          messageJson: msg,
        ));
      } else {
        await ChatPendingSendPrefs.remove(tempMessageId);
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.mediaGroup,
          ownerUserId: ownerUserId,
          conversationId: conversationId,
          success: false,
          tempMessageId: tempMessageId,
          error: 'Invalid response',
          restoreFiles: restoreFiles,
          restoreCaption: restoreCaption,
        ));
      }
    } catch (e) {
      // An interrupted session (account switch / logout mid-flight) is not a
      // transport failure, but the logical send is still the previous owner's:
      // keep it, owner-stamped, so only that account can resume it.
      if (e is ApiSessionChangedException || isRetryableChatSendError(e)) {
        if (ownerUserId != null) {
          await ChatPendingSendPrefs.upsert(ChatPendingSendRecord(
          id: tempMessageId,
          conversationId: conversationId,
          ownerUserId: ownerUserId,
          kind: _kindToStorageString(OutgoingChatSendKind.mediaGroup),
          idempotencyKey: idempotencyKey,
          content: caption,
          receiverId: receiverId,
          replyToMessageId: replyToMessageId,
          replyToPreviewJson: replyToPreviewJson,
          listingPreview: listingPreview,
          filePaths: files.map((f) => f.path).toList(),
          createdAt: createdAt.millisecondsSinceEpoch,
          attempts: e is ApiSessionChangedException
              ? max(0, attemptNumber - 1)
              : attemptNumber,
          lastAttemptAt: DateTime.now().millisecondsSinceEpoch,
          lastError: e.toString(),
        ));
        }
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.mediaGroup,
          ownerUserId: ownerUserId,
          conversationId: conversationId,
          success: false,
          tempMessageId: tempMessageId,
          errorCause: e,
          pendingRetry: true,
        ));
      } else {
        await ChatPendingSendPrefs.remove(tempMessageId);
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.mediaGroup,
          ownerUserId: ownerUserId,
          conversationId: conversationId,
          success: false,
          tempMessageId: tempMessageId,
          errorCause: e,
          restoreFiles: restoreFiles,
          restoreCaption: restoreCaption,
        ));
      }
    } finally {
      _inFlightMediaByTempId.remove(tempMessageId);
    }
  }

  void startAudioSend({
    required String conversationId,
    required XFile audioFile,
    required String tempMessageId,
    required DateTime startedAt,
    String? receiverId,
    String? replyToMessageId,
    required XFile restoreFile,
    String? expectedOwnerUserId,
  }) {
    final session = _sessionForNewSend(expectedOwnerUserId);
    if (session == null) {
      _emit(OutgoingChatSendEvent(
        kind: OutgoingChatSendKind.audio,
        ownerUserId: expectedOwnerUserId ?? ApiService.currentAccountId,
        conversationId: conversationId,
        success: false,
        tempMessageId: tempMessageId,
        errorCause: ApiSessionChangedException(),
        restoreFiles: [restoreFile],
      ));
      return;
    }
    final idempotencyKey = _newChatIdempotencyKey();
    unawaited(_runAudioSend(
      session: session,
      conversationId: conversationId,
      audioFile: audioFile,
      tempMessageId: tempMessageId,
      idempotencyKey: idempotencyKey,
      receiverId: receiverId,
      replyToMessageId: replyToMessageId,
      restoreFile: restoreFile,
      createdAt: startedAt,
      attemptNumber: 1,
    ));
  }

  Future<void> _runAudioSend({
    required String conversationId,
    required XFile audioFile,
    required String tempMessageId,
    required String idempotencyKey,
    String? receiverId,
    String? replyToMessageId,
    required XFile restoreFile,
    required DateTime createdAt,
    required int attemptNumber,
    required AuthSessionSnapshot session,
  }) async {
    // BE-18: one key for this whole logical send attempt. The 404 fallback
    // below (older backend without /send_audio) is still the same logical
    // send, just a different endpoint, so it intentionally reuses the same
    // key rather than generating a new one.
    final ownerUserId = session.accountId;
    try {
      _assertSessionStillOwner(session);
      Map<String, dynamic> response;
      try {
        response = await ApiService.sendChatAudio(
          conversationId: conversationId,
          audioFile: audioFile,
          receiverId: receiverId,
          replyToMessageId: replyToMessageId,
          idempotencyKey: idempotencyKey,
        );
      } on ApiException catch (e) {
        // Older APIs expose voice via send_media_group only.
        if (e.statusCode != 404) rethrow;
        response = await ApiService.sendChatMediaGroup(
          conversationId: conversationId,
          files: [audioFile],
          receiverId: receiverId,
          replyToMessageId: replyToMessageId,
          idempotencyKey: idempotencyKey,
        );
      }
      final msg = response['message'];
      if (msg is Map<String, dynamic>) {
        await ChatPendingSendPrefs.remove(tempMessageId);
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.audio,
          ownerUserId: ownerUserId,
          conversationId: conversationId,
          success: true,
          tempMessageId: tempMessageId,
          messageJson: msg,
        ));
      } else {
        await ChatPendingSendPrefs.remove(tempMessageId);
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.audio,
          ownerUserId: ownerUserId,
          conversationId: conversationId,
          success: false,
          tempMessageId: tempMessageId,
          error: 'Invalid response',
          restoreFiles: [restoreFile],
        ));
      }
    } catch (e) {
      // An interrupted session (account switch / logout mid-flight) is not a
      // transport failure, but the logical send is still the previous owner's:
      // keep it, owner-stamped, so only that account can resume it.
      if (e is ApiSessionChangedException || isRetryableChatSendError(e)) {
        if (ownerUserId != null) {
          await ChatPendingSendPrefs.upsert(ChatPendingSendRecord(
          id: tempMessageId,
          conversationId: conversationId,
          ownerUserId: ownerUserId,
          kind: _kindToStorageString(OutgoingChatSendKind.audio),
          idempotencyKey: idempotencyKey,
          receiverId: receiverId,
          replyToMessageId: replyToMessageId,
          filePaths: [audioFile.path],
          createdAt: createdAt.millisecondsSinceEpoch,
          attempts: e is ApiSessionChangedException
              ? max(0, attemptNumber - 1)
              : attemptNumber,
          lastAttemptAt: DateTime.now().millisecondsSinceEpoch,
          lastError: e.toString(),
        ));
        }
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.audio,
          ownerUserId: ownerUserId,
          conversationId: conversationId,
          success: false,
          tempMessageId: tempMessageId,
          errorCause: e,
          pendingRetry: true,
        ));
      } else {
        await ChatPendingSendPrefs.remove(tempMessageId);
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.audio,
          ownerUserId: ownerUserId,
          conversationId: conversationId,
          success: false,
          tempMessageId: tempMessageId,
          errorCause: e,
          restoreFiles: [restoreFile],
        ));
      }
    }
  }

  void startTextMessageSend({
    required String conversationId,
    required String content,
    String? receiverId,
    Map<String, dynamic>? listingPreview,
    String? replyToMessageId,
    String? tempMessageId,
    String? expectedOwnerUserId,
  }) {
    final session = _sessionForNewSend(expectedOwnerUserId);
    final resolvedTempId = tempMessageId ?? _newTempMessageId();
    if (session == null) {
      _emit(OutgoingChatSendEvent(
        kind: OutgoingChatSendKind.textMessage,
        ownerUserId: expectedOwnerUserId ?? ApiService.currentAccountId,
        conversationId: conversationId,
        success: false,
        tempMessageId: resolvedTempId,
        restoredPlainText: content,
        errorCause: ApiSessionChangedException(),
      ));
      return;
    }
    final idempotencyKey = _newChatIdempotencyKey();
    unawaited(_runTextSend(
      session: session,
      conversationId: conversationId,
      content: content,
      receiverId: receiverId,
      listingPreview: listingPreview,
      replyToMessageId: replyToMessageId,
      idempotencyKey: idempotencyKey,
      // Defensive fallback so persistence still has a stable key even if a
      // caller does not pass one (keeps this parameter backward compatible).
      tempMessageId: resolvedTempId,
      createdAt: DateTime.now(),
      attemptNumber: 1,
    ));
  }

  Future<void> _runTextSend({
    required String conversationId,
    required String content,
    required String idempotencyKey,
    required String tempMessageId,
    required DateTime createdAt,
    required int attemptNumber,
    required AuthSessionSnapshot session,
    String? receiverId,
    Map<String, dynamic>? listingPreview,
    String? replyToMessageId,
    Map<String, dynamic>? replyToPreviewJson,
  }) async {
    // BE-18: one key for this whole logical send attempt (this is the path
    // exercised by the automatic timeout retry in `_sendWithAdaptiveTimeout`
    // — the same key rides along on that retry because it is baked into the
    // headers for this single `sendChatMessageByConversation` call below).
    final ownerUserId = session.accountId;
    try {
      _assertSessionStillOwner(session);
      final response = await ApiService.sendChatMessageByConversation(
        conversationId: conversationId,
        content: content,
        receiverId: receiverId,
        listingPreview: listingPreview,
        replyToMessageId: replyToMessageId,
        idempotencyKey: idempotencyKey,
      );
      final msg = response['message'];
      if (msg is Map<String, dynamic>) {
        await ChatPendingSendPrefs.remove(tempMessageId);
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.textMessage,
          ownerUserId: ownerUserId,
          conversationId: conversationId,
          success: true,
          tempMessageId: tempMessageId,
          messageJson: msg,
        ));
      } else {
        await ChatPendingSendPrefs.remove(tempMessageId);
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.textMessage,
          ownerUserId: ownerUserId,
          conversationId: conversationId,
          success: false,
          tempMessageId: tempMessageId,
          restoredPlainText: content,
          error: 'Invalid response',
        ));
      }
    } catch (e) {
      // An interrupted session (account switch / logout mid-flight) is not a
      // transport failure, but the logical send is still the previous owner's:
      // keep it, owner-stamped, so only that account can resume it.
      if (e is ApiSessionChangedException || isRetryableChatSendError(e)) {
        if (ownerUserId != null) {
          await ChatPendingSendPrefs.upsert(ChatPendingSendRecord(
          id: tempMessageId,
          conversationId: conversationId,
          ownerUserId: ownerUserId,
          kind: _kindToStorageString(OutgoingChatSendKind.textMessage),
          idempotencyKey: idempotencyKey,
          content: content,
          receiverId: receiverId,
          replyToMessageId: replyToMessageId,
          replyToPreviewJson: replyToPreviewJson,
          listingPreview: listingPreview,
          createdAt: createdAt.millisecondsSinceEpoch,
          attempts: e is ApiSessionChangedException
              ? max(0, attemptNumber - 1)
              : attemptNumber,
          lastAttemptAt: DateTime.now().millisecondsSinceEpoch,
          lastError: e.toString(),
        ));
        }
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.textMessage,
          ownerUserId: ownerUserId,
          conversationId: conversationId,
          success: false,
          tempMessageId: tempMessageId,
          errorCause: e,
          pendingRetry: true,
        ));
      } else {
        await ChatPendingSendPrefs.remove(tempMessageId);
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.textMessage,
          ownerUserId: ownerUserId,
          conversationId: conversationId,
          success: false,
          tempMessageId: tempMessageId,
          restoredPlainText: content,
          errorCause: e,
        ));
      }
    }
  }

  Future<List<XFile>> _resolveExistingFiles(List<String> paths) async {
    final out = <XFile>[];
    for (final p in paths) {
      if (p.trim().isEmpty) continue;
      try {
        if (await File(p).exists()) out.add(XFile(p));
      } catch (e, st) {
        logNonFatal(e, st);
      }
    }
    return out;
  }

  Future<void> _retryPersistedRecord(
    ChatPendingSendRecord record,
    AuthSessionSnapshot session,
  ) async {
    final ownerUserId = record.ownerUserId;
    // Defense in depth: a record is only ever resumed by its own owner.
    if (session.accountId != ownerUserId) return;
    final kind = _kindFromStorageString(record.kind);
    if (kind == null) {
      // Unknown/corrupt kind — cannot safely retry; drop it rather than
      // spin on it forever.
      await ChatPendingSendPrefs.remove(record.id);
      return;
    }
    _retryInProgressIds.add(record.id);
    try {
      final createdAt = DateTime.fromMillisecondsSinceEpoch(record.createdAt);
      final nextAttempt = record.attempts + 1;
      switch (kind) {
        case OutgoingChatSendKind.textMessage:
          await _runTextSend(
            conversationId: record.conversationId,
            content: record.content ?? '',
            receiverId: record.receiverId,
            listingPreview: record.listingPreview,
            replyToMessageId: record.replyToMessageId,
            replyToPreviewJson: record.replyToPreviewJson,
            idempotencyKey: record.idempotencyKey,
            tempMessageId: record.id,
            createdAt: createdAt,
            attemptNumber: nextAttempt,
            session: session,
          );
          break;
        case OutgoingChatSendKind.mediaGroup:
          final files = await _resolveExistingFiles(record.filePaths);
          if (files.isEmpty) {
            await ChatPendingSendPrefs.remove(record.id);
            _emit(OutgoingChatSendEvent(
              kind: OutgoingChatSendKind.mediaGroup,
              ownerUserId: ownerUserId,
              conversationId: record.conversationId,
              success: false,
              tempMessageId: record.id,
              error: 'Attachments are no longer available on this device',
            ));
            break;
          }
          _inFlightMediaByTempId[record.id] = InFlightMediaSend(
            ownerUserId: ownerUserId,
            conversationId: record.conversationId,
            tempMessageId: record.id,
            files: files,
            startedAt: createdAt,
            receiverId: record.receiverId,
            listingPreview: record.listingPreview,
            replyToMessageId: record.replyToMessageId,
            replyToPreviewJson: record.replyToPreviewJson,
          );
          await _runMediaGroupSend(
            conversationId: record.conversationId,
            files: files,
            tempMessageId: record.id,
            idempotencyKey: record.idempotencyKey,
            receiverId: record.receiverId,
            caption: record.content,
            replyToMessageId: record.replyToMessageId,
            replyToPreviewJson: record.replyToPreviewJson,
            listingPreview: record.listingPreview,
            restoreFiles: files,
            restoreCaption: record.content,
            createdAt: createdAt,
            attemptNumber: nextAttempt,
            session: session,
          );
          break;
        case OutgoingChatSendKind.audio:
          final files = await _resolveExistingFiles(record.filePaths);
          if (files.isEmpty) {
            await ChatPendingSendPrefs.remove(record.id);
            _emit(OutgoingChatSendEvent(
              kind: OutgoingChatSendKind.audio,
              ownerUserId: ownerUserId,
              conversationId: record.conversationId,
              success: false,
              tempMessageId: record.id,
              error: 'Recording is no longer available on this device',
            ));
            break;
          }
          await _runAudioSend(
            conversationId: record.conversationId,
            audioFile: files.first,
            tempMessageId: record.id,
            idempotencyKey: record.idempotencyKey,
            receiverId: record.receiverId,
            replyToMessageId: record.replyToMessageId,
            restoreFile: files.first,
            createdAt: createdAt,
            attemptNumber: nextAttempt,
            session: session,
          );
          break;
      }
    } finally {
      _retryInProgressIds.remove(record.id);
    }
  }

  /// F-11: attempt to (re)send every eligible durable pending send —
  /// optionally scoped to a single [conversationId] — reusing each
  /// record's original idempotency key. Eligible means: not already being
  /// retried, not still tracked as actively in-flight, under
  /// [maxAutoRetryAttempts], and at least [minAutoRetryInterval] since its
  /// last attempt. Safe to call repeatedly/concurrently (bounded, self
  /// deduplicating) from app bootstrap, chat-page open, and connectivity
  /// callbacks alike.
  Future<void> recoverPendingSends({String? conversationId}) async {
    if (_recoveryScanRunning) return;
    _recoveryScanRunning = true;
    try {
      // F-34/F-35: only the signed-in, verified account's records are ever
      // considered; everyone else's stay on disk untouched until that account
      // signs in again.
      final session = ApiService.captureSession();
      final owner = session.accountId;
      if (!session.authenticated || owner == null) return;
      final records = conversationId == null
          ? await ChatPendingSendPrefs.loadForOwner(owner)
          : await ChatPendingSendPrefs.loadForConversation(
              conversationId,
              ownerUserId: owner,
            );
      if (records.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final record in records) {
        if (_retryInProgressIds.contains(record.id)) continue;
        if (_inFlightMediaByTempId.containsKey(record.id)) continue;
        if (record.attempts >= maxAutoRetryAttempts) continue;
        final last = record.lastAttemptAt;
        if (last != null &&
            (now - last) < minAutoRetryInterval.inMilliseconds) {
          continue;
        }
        if (!ApiService.isSessionCurrent(session)) break;
        unawaited(_retryPersistedRecord(record, session));
      }
    } catch (e, st) {
      logNonFatal(e, st);
    } finally {
      _recoveryScanRunning = false;
    }
  }
}
