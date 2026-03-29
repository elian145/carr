import 'dart:async';

import 'package:image_picker/image_picker.dart';

import 'api_service.dart';

enum OutgoingChatSendKind { mediaGroup, textMessage }

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
    try {
      final response = await ApiService.sendChatMediaGroup(
        conversationId: conversationId,
        files: files,
        receiverId: receiverId,
        caption: caption,
        replyToMessageId: replyToMessageId,
        listingPreview: listingPreview,
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
        error: e.toString(),
        restoreFiles: restoreFiles,
        restoreCaption: restoreCaption,
      ));
    } finally {
      _inFlightMediaByTempId.remove(tempMessageId);
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
    try {
      final response = await ApiService.sendChatMessageByConversation(
        conversationId: conversationId,
        content: content,
        receiverId: receiverId,
        listingPreview: listingPreview,
        replyToMessageId: replyToMessageId,
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
        error: e.toString(),
      ));
    }
  }
}
