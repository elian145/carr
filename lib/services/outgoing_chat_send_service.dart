import 'dart:async';
import 'dart:math';

import 'package:image_picker/image_picker.dart';

import 'api_service.dart';

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

enum OutgoingChatSendKind { mediaGroup, textMessage, audio }

/// Snapshot of a media upload still in progress (survives leaving the chat screen).
class InFlightMediaSend {
  InFlightMediaSend({
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
    required this.conversationId,
    required this.success,
    this.tempMessageId,
    this.messageJson,
    this.error,
    this.errorCause,
    this.restoreFiles,
    this.restoreCaption,
    this.restoredPlainText,
  });

  final OutgoingChatSendKind kind;
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
}

/// Fire-and-forget chat sends so uploads continue if the user leaves the screen.
/// Results are delivered on [events] (best-effort while a listener is active).
class OutgoingChatSendService {
  OutgoingChatSendService._();
  static final OutgoingChatSendService instance = OutgoingChatSendService._();

  final StreamController<OutgoingChatSendEvent> _controller =
      StreamController<OutgoingChatSendEvent>.broadcast();

  Stream<OutgoingChatSendEvent> get events => _controller.stream;

  final Map<String, InFlightMediaSend> _inFlightMediaByTempId = {};

  /// Active media uploads keyed by temp message id.
  List<InFlightMediaSend> inFlightMediaForConversation(String conversationId) {
    return _inFlightMediaByTempId.values
        .where((e) => e.conversationId == conversationId)
        .toList(growable: false);
  }

  /// Stop tracking an upload (user discarded / recalled); the HTTP call may still finish.
  void discardInFlightMedia(String tempMessageId) {
    _inFlightMediaByTempId.remove(tempMessageId);
  }

  void _emit(OutgoingChatSendEvent e) {
    if (!_controller.isClosed) {
      _controller.add(e);
    }
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
  }) {
    _inFlightMediaByTempId[tempMessageId] = InFlightMediaSend(
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
    unawaited(_runMediaGroupSend(
      conversationId: conversationId,
      files: files,
      tempMessageId: tempMessageId,
      receiverId: receiverId,
      caption: caption,
      replyToMessageId: replyToMessageId,
      listingPreview: listingPreview,
      restoreFiles: restoreFiles,
      restoreCaption: restoreCaption,
    ));
  }

  Future<void> _runMediaGroupSend({
    required String conversationId,
    required List<XFile> files,
    required String tempMessageId,
    String? receiverId,
    String? caption,
    String? replyToMessageId,
    Map<String, dynamic>? listingPreview,
    required List<XFile> restoreFiles,
    String? restoreCaption,
  }) async {
    // BE-18: one key for this whole logical send attempt (including any
    // automatic transport retry of the same HTTP call below).
    final idempotencyKey = _newChatIdempotencyKey();
    try {
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
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.mediaGroup,
          conversationId: conversationId,
          success: true,
          tempMessageId: tempMessageId,
          messageJson: msg,
        ));
      } else {
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.mediaGroup,
          conversationId: conversationId,
          success: false,
          tempMessageId: tempMessageId,
          error: 'Invalid response',
          restoreFiles: restoreFiles,
          restoreCaption: restoreCaption,
        ));
      }
    } catch (e) {
      _emit(OutgoingChatSendEvent(
        kind: OutgoingChatSendKind.mediaGroup,
        conversationId: conversationId,
        success: false,
        tempMessageId: tempMessageId,
        errorCause: e,
        restoreFiles: restoreFiles,
        restoreCaption: restoreCaption,
      ));
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
  }) {
    unawaited(_runAudioSend(
      conversationId: conversationId,
      audioFile: audioFile,
      tempMessageId: tempMessageId,
      receiverId: receiverId,
      replyToMessageId: replyToMessageId,
      restoreFile: restoreFile,
    ));
  }

  Future<void> _runAudioSend({
    required String conversationId,
    required XFile audioFile,
    required String tempMessageId,
    String? receiverId,
    String? replyToMessageId,
    required XFile restoreFile,
  }) async {
    // BE-18: one key for this whole logical send attempt. The 404 fallback
    // below (older backend without /send_audio) is still the same logical
    // send, just a different endpoint, so it intentionally reuses the same
    // key rather than generating a new one.
    final idempotencyKey = _newChatIdempotencyKey();
    try {
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
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.audio,
          conversationId: conversationId,
          success: true,
          tempMessageId: tempMessageId,
          messageJson: msg,
        ));
      } else {
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.audio,
          conversationId: conversationId,
          success: false,
          tempMessageId: tempMessageId,
          error: 'Invalid response',
          restoreFiles: [restoreFile],
        ));
      }
    } catch (e) {
      _emit(OutgoingChatSendEvent(
        kind: OutgoingChatSendKind.audio,
        conversationId: conversationId,
        success: false,
        tempMessageId: tempMessageId,
        errorCause: e,
        restoreFiles: [restoreFile],
      ));
    }
  }

  void startTextMessageSend({
    required String conversationId,
    required String content,
    String? receiverId,
    Map<String, dynamic>? listingPreview,
    String? replyToMessageId,
  }) {
    unawaited(_runTextSend(
      conversationId: conversationId,
      content: content,
      receiverId: receiverId,
      listingPreview: listingPreview,
      replyToMessageId: replyToMessageId,
    ));
  }

  Future<void> _runTextSend({
    required String conversationId,
    required String content,
    String? receiverId,
    Map<String, dynamic>? listingPreview,
    String? replyToMessageId,
  }) async {
    // BE-18: one key for this whole logical send attempt (this is the path
    // exercised by the automatic timeout retry in `_sendWithAdaptiveTimeout`
    // — the same key rides along on that retry because it is baked into the
    // headers for this single `sendChatMessageByConversation` call below).
    final idempotencyKey = _newChatIdempotencyKey();
    try {
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
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.textMessage,
          conversationId: conversationId,
          success: true,
          messageJson: msg,
        ));
      } else {
        _emit(OutgoingChatSendEvent(
          kind: OutgoingChatSendKind.textMessage,
          conversationId: conversationId,
          success: false,
          restoredPlainText: content,
          error: 'Invalid response',
        ));
      }
    } catch (e) {
      _emit(OutgoingChatSendEvent(
        kind: OutgoingChatSendKind.textMessage,
        conversationId: conversationId,
        success: false,
        restoredPlainText: content,
        errorCause: e,
      ));
    }
  }
}
