part of '../api_service.dart';

/// Chat HTTP + attachments (split from [ApiService]).
abstract final class _ApiServiceChat {
  _ApiServiceChat._();

    static Future<Map<String, dynamic>> sendChatMessageByConversation({
      required String conversationId,
      required String content,
      String? receiverId,
      Map<String, dynamic>? listingPreview,
      String? replyToMessageId,
    }) async {
      final payload = <String, dynamic>{'content': content};
      if (receiverId != null && receiverId.trim().isNotEmpty) {
        payload['receiver_id'] = receiverId.trim();
      }
      if (listingPreview != null && listingPreview.isNotEmpty) {
        payload['listing_preview'] = listingPreview;
      }
      if (replyToMessageId != null && replyToMessageId.trim().isNotEmpty) {
        payload['reply_to_message_id'] = replyToMessageId.trim();
      }
      return await ApiService._makeAuthenticatedRequest(
        'POST',
        '/chat/$conversationId/send',
        body: payload,
      );
    }

    static Future<int> getUnreadChatCount() async {
      final result = await ApiService._makeAuthenticatedRequest('GET', '/chat/unread_count');
      return (result['unread_count'] as num?)?.toInt() ?? 0;
    }

    /// Load chat history for a listing conversation (car public_id or numeric id).
    ///
    /// Returns a map with keys: `messages` (list), `page`, `per_page`, `total`, `has_more`.
    static Future<Map<String, dynamic>> getChatMessagesByConversation(
      String conversationId, {
      int page = 1,
      int perPage = 50,
    }) async {
      final endpoint =
          '/chat/$conversationId/messages?page=$page&per_page=$perPage';
      final url = Uri.parse('${ApiService.baseUrl}$endpoint');
      Map<String, String> headers = ApiService._getHeaders();

      http.Response response = await ApiService._httpClient
          .get(url, headers: headers)
          .timeout(ApiService._defaultTimeout);

      if (response.statusCode == 401) {
        final refreshed = await ApiService._refreshAccessToken();
        if (!refreshed) {
          await ApiService.clearTokens();
          throw Exception('Authentication failed');
        }
        headers = ApiService._getHeaders();
        response = await ApiService._httpClient.get(url, headers: headers).timeout(ApiService._defaultTimeout);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        ApiService._handleResponse(response);
      }

      if (response.body.trim().isEmpty) {
        return {
          'messages': <Map<String, dynamic>>[],
          'has_more': false,
          'total': 0,
          'page': page,
        };
      }
      final decoded = json.decode(response.body);

      List<Map<String, dynamic>> messages = [];
      bool hasMore = false;
      int total = 0;

      if (decoded is Map) {
        if (decoded['messages'] is List) {
          messages = (decoded['messages'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
              .toList();
        }
        hasMore = decoded['has_more'] == true;
        total = (decoded['total'] as num?)?.toInt() ?? messages.length;
      } else if (decoded is List) {
        messages = decoded
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
            .toList();
      }

      return {
        'messages': messages,
        'has_more': hasMore,
        'total': total,
        'page': page,
      };
    }

    /// Upload an image and send it as a chat message.
    static Future<Map<String, dynamic>> sendChatImage({
      required String conversationId,
      required XFile imageFile,
      String? receiverId,
      String? caption,
      String? replyToMessageId,
    }) async {
      return _sendChatAttachment(
        conversationId: conversationId,
        endpointSuffix: 'send_image',
        fieldName: 'image',
        file: imageFile,
        receiverId: receiverId,
        caption: caption,
        replyToMessageId: replyToMessageId,
      );
    }

    static Future<Map<String, dynamic>> sendChatVideo({
      required String conversationId,
      required XFile videoFile,
      String? receiverId,
      String? caption,
      String? replyToMessageId,
    }) async {
      return _sendChatAttachment(
        conversationId: conversationId,
        endpointSuffix: 'send_video',
        fieldName: 'video',
        file: videoFile,
        receiverId: receiverId,
        caption: caption,
        replyToMessageId: replyToMessageId,
      );
    }

    static Future<Map<String, dynamic>> sendChatAudio({
      required String conversationId,
      required XFile audioFile,
      String? receiverId,
      String? replyToMessageId,
    }) async {
      return _sendChatAttachment(
        conversationId: conversationId,
        endpointSuffix: 'send_audio',
        fieldName: 'audio',
        file: audioFile,
        receiverId: receiverId,
        replyToMessageId: replyToMessageId,
      );
    }

    static Future<Map<String, dynamic>> sendChatMediaGroup({
      required String conversationId,
      required List<XFile> files,
      String? receiverId,
      String? caption,
      String? replyToMessageId,
      Map<String, dynamic>? listingPreview,
    }) async {
      if (files.isEmpty) {
        throw Exception('No attachments selected');
      }
      final url = Uri.parse('${ApiService.baseUrl}/chat/$conversationId/send_media_group');

      Future<http.Response> makeRequest() async {
        final req = http.MultipartRequest('POST', url);
        req.headers.addAll(ApiService._getHeaders());
        for (final file in files) {
          req.files.add(
            await http.MultipartFile.fromPath('attachments', file.path),
          );
        }
        if (receiverId != null && receiverId.trim().isNotEmpty) {
          req.fields['receiver_id'] = receiverId.trim();
        }
        if (caption != null && caption.trim().isNotEmpty) {
          req.fields['content'] = caption.trim();
        }
        if (replyToMessageId != null && replyToMessageId.trim().isNotEmpty) {
          req.fields['reply_to_message_id'] = replyToMessageId.trim();
        }
        if (listingPreview != null && listingPreview.isNotEmpty) {
          req.fields['listing_preview'] = json.encode(listingPreview);
        }
        final streamedResponse = await req.send().timeout(ApiService._uploadTimeout);
        return http.Response.fromStream(streamedResponse);
      }

      var response = await makeRequest();
      if (response.statusCode == 401) {
        final refreshed = await ApiService._refreshAccessToken();
        if (!refreshed) {
          await ApiService.clearTokens();
          throw Exception('Authentication failed');
        }
        response = await makeRequest();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        ApiService._handleResponse(response);
      }
      return json.decode(response.body) as Map<String, dynamic>;
    }

    static Future<Map<String, dynamic>> _sendChatAttachment({
      required String conversationId,
      required String endpointSuffix,
      required String fieldName,
      required XFile file,
      String? receiverId,
      String? caption,
      String? replyToMessageId,
    }) async {
      final url = Uri.parse('${ApiService.baseUrl}/chat/$conversationId/$endpointSuffix');

      Future<http.Response> makeRequest() async {
        final req = http.MultipartRequest('POST', url);
        req.headers.addAll(ApiService._getHeaders());
        req.files.add(await http.MultipartFile.fromPath(fieldName, file.path));
        if (receiverId != null && receiverId.trim().isNotEmpty) {
          req.fields['receiver_id'] = receiverId.trim();
        }
        if (caption != null && caption.trim().isNotEmpty) {
          req.fields['content'] = caption.trim();
        }
        if (replyToMessageId != null && replyToMessageId.trim().isNotEmpty) {
          req.fields['reply_to_message_id'] = replyToMessageId.trim();
        }
        final streamedResponse = await req.send().timeout(ApiService._uploadTimeout);
        return http.Response.fromStream(streamedResponse);
      }

      var response = await makeRequest();
      if (response.statusCode == 401) {
        final refreshed = await ApiService._refreshAccessToken();
        if (!refreshed) {
          await ApiService.clearTokens();
          throw Exception('Authentication failed');
        }
        response = await makeRequest();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        ApiService._handleResponse(response);
      }
      return json.decode(response.body) as Map<String, dynamic>;
    }

    static Future<Map<String, dynamic>> editChatMessage({
      required String messageId,
      required String content,
      List<Map<String, dynamic>>? attachments,
    }) async {
      final body = <String, dynamic>{'content': content};
      if (attachments != null) {
        body['attachments'] = attachments;
      }
      return await ApiService._makeAuthenticatedRequest(
        'PATCH',
        '/chat/messages/$messageId',
        body: body,
      );
    }

    static Future<Map<String, dynamic>> deleteChatMessage({
      required String messageId,
    }) async {
      return await ApiService._makeAuthenticatedRequest(
        'DELETE',
        '/chat/messages/$messageId',
      );
    }
    // Load recent chat conversations for the current user.
    static Future<List<Map<String, dynamic>>> getChats() async {
      final endpoint = '/chats';
      final url = Uri.parse('${ApiService.baseUrl}$endpoint');
      Map<String, String> headers = ApiService._getHeaders();

      http.Response response = await ApiService._httpClient
          .get(url, headers: headers)
          .timeout(ApiService._defaultTimeout);

      if (response.statusCode == 401) {
        final refreshed = await ApiService._refreshAccessToken();
        if (!refreshed) {
          await ApiService.clearTokens();
          throw Exception('Authentication failed');
        }
        headers = ApiService._getHeaders();
        response = await ApiService._httpClient.get(url, headers: headers).timeout(ApiService._defaultTimeout);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        ApiService._handleResponse(response); // Throws ApiException.
      }

      if (response.body.trim().isEmpty) return <Map<String, dynamic>>[];
      final decoded = json.decode(response.body);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
            .toList();
      }
      if (decoded is Map && decoded['chats'] is List) {
        final raw = decoded['chats'] as List;
        return raw
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
            .toList();
      }
      return <Map<String, dynamic>>[];
    }
}
