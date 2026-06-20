import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/websocket_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/outgoing_chat_send_service.dart';
import '../shared/auth/phone_verification_gate.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/media/media_url.dart';
import '../shared/text/pretty_title_case.dart';
import '../data/car_name_translations.dart';
import '../theme_provider.dart';
import '../widgets/theme_toggle_widget.dart';
import '../widgets/in_app_video_screen.dart';


part 'chat/chat_widgets.dart';
part 'chat/chat_list_page.dart';
part 'chat/chat_notifications_page.dart';
part 'chat/chat_conversation_history.dart';
part 'chat/chat_conversation_transport.dart';
part 'chat/chat_conversation_actions.dart';
part 'chat/chat_conversation_composer_ui.dart';
part 'chat/chat_conversation_message_ui.dart';
part 'chat/chat_conversation_layout.dart';

const Color _kComposerOutlineOrange = Color(0xFFFF7A00);

/// Brand orange (matches home [buildGlobalCarCard]); explicit color avoids
/// [Theme.primaryColor] matching surfaces inside chat bubbles in dark mode.
const Color _kChatListingCardAccentOrange = Color(0xFFFF6B00);

/// Peer bubble / preview fill: same look as dark mode (frosted on dark shell; solid blend on light shell).
Color _homeListingCardBackgroundFill(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) {
    return Colors.white.withValues(alpha: 0.10);
  }
  return AppThemes.listingCardFillGridOnLightShell();
}

String _digitsLocalized(BuildContext context, String input) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar' || code == 'ku' || code == 'ckb') {
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var out = input;
    for (int i = 0; i < western.length; i++) {
      out = out.replaceAll(western[i], eastern[i]);
    }
    return out;
  }
  return input;
}

Widget buildChatListingAvatar(
  BuildContext context, {
  String? imageUrl,
  double radius = 24,
}) {
  final cs = Theme.of(context).colorScheme;
  final resolved = (imageUrl ?? '').trim();
  final size = radius * 2;
  final fallback = Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: cs.primary.withAlpha(30),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.directions_car,
      color: cs.primary,
      size: radius * 0.85,
    ),
  );
  if (resolved.isEmpty) return fallback;
  return SizedBox(
    width: size,
    height: size,
    child: ClipOval(
      child: Image.network(
        resolved,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: size,
            height: size,
            color: cs.primary.withAlpha(30),
            alignment: Alignment.center,
            child: SizedBox(
              width: radius,
              height: radius,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
          );
        },
      ),
    ),
  );
}

String _relativeTime(BuildContext context, DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime.toLocal());
  final loc = AppLocalizations.of(context)!;
  String formatNum(int n) => _digitsLocalized(context, n.toString());
  if (diff.isNegative) {
    return loc.justNow;
  }
  if (diff.inDays > 0) {
    return loc.timeDaysAgo(formatNum(diff.inDays));
  } else if (diff.inHours > 0) {
    return loc.timeHoursAgo(formatNum(diff.inHours));
  } else if (diff.inMinutes > 0) {
    return loc.timeMinutesAgo(formatNum(diff.inMinutes));
  }
  return loc.justNow;
}

/// Best-effort timestamp string from API (snake_case / camelCase / conversation fallbacks).
String _rawChatListTimestamp(
  Map<String, dynamic> last,
  Map<String, dynamic> conversation,
) {
  String pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s != 'null') return s;
    }
    return '';
  }

  var s = pick(last, [
    'created_at',
    'createdAt',
    'updated_at',
    'updatedAt',
    'timestamp',
    'time',
    'sent_at',
    'sentAt',
  ]);
  if (s.isNotEmpty) return s;
  s = pick(conversation, [
    'updated_at',
    'updatedAt',
    'last_activity_at',
    'lastActivityAt',
  ]);
  return s;
}

String _noMessagesText(BuildContext context) {
  return AppLocalizations.of(context)!.noMessagesYet;
}

String _chatText(BuildContext context, String en, {String? ar, String? ku}) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return ar ?? en;
  if (code == 'ku' || code == 'ckb') return ku ?? en;
  return en;
}

String _chatEditedLabel(BuildContext context) =>
    _chatText(context, 'Edited', ar: 'معدّل', ku: 'دەستکاری کراو');

String _chatMessageDeletedText(BuildContext context) => _chatText(
      context,
      'This message was deleted',
      ar: 'تم حذف هذه الرسالة',
      ku: 'ئەم پەیامە سڕایەوە',
    );

String _chatDisplayContent(BuildContext context, ChatMessage message) {
  if (message.isDeleted) return _chatMessageDeletedText(context);
  return message.content;
}

/// Listing title in the active app language (brand/model translated; trim kept in English).
String localizedListingTitle(BuildContext context, Map<String, dynamic> car) {
  final brand = (car['brand'] ?? '').toString().trim();
  final model = (car['model'] ?? '').toString().trim();
  if (brand.isNotEmpty && model.isNotEmpty) {
    final base = CarNameTranslations.getLocalizedCarTitleNoYear(context, car);
    final trim = (car['trim'] ?? '').toString().trim();
    final year = (car['year'] ?? '').toString().trim();
    final parts = <String>[
      if (base.isNotEmpty) base,
      if (trim.isNotEmpty && trim.toLowerCase() != 'base') prettyTitleCase(trim),
      if (year.isNotEmpty) year,
    ];
    final built = parts.join(' ').trim();
    if (built.isNotEmpty) {
      // Avoid Latin title-casing on Arabic/Kurdish text.
      return built;
    }
  }

  final localized =
      CarNameTranslations.getLocalizedCarTitle(context, car).trim();
  if (localized.isNotEmpty) {
    return RegExp(r'[A-Za-z]').hasMatch(localized)
        ? prettyTitleCase(localized)
        : localized;
  }
  final fallback = (car['title'] ?? '').toString().trim();
  if (fallback.isNotEmpty) return prettyTitleCase(fallback);
  return '';
}

/// Build car map for [localizedListingTitle] from a chat list row or route args.
Map<String, dynamic> listingMetaFromChatRow(Map<String, dynamic> source) {
  final brand =
      (source['car_brand'] ?? source['brand'] ?? '').toString().trim();
  final model =
      (source['car_model'] ?? source['model'] ?? '').toString().trim();
  final hasIdentity = brand.isNotEmpty && model.isNotEmpty;

  return {
    if (brand.isNotEmpty) 'brand': brand,
    if (model.isNotEmpty) 'model': model,
    if ((source['car_trim'] ?? source['trim'] ?? '').toString().trim().isNotEmpty)
      'trim': (source['car_trim'] ?? source['trim']).toString(),
    if ((source['car_year'] ?? source['year'] ?? '').toString().trim().isNotEmpty)
      'year': (source['car_year'] ?? source['year']).toString(),
    if (!hasIdentity &&
        (source['car_title'] ?? source['title'] ?? '').toString().trim().isNotEmpty)
      'title': (source['car_title'] ?? source['title']).toString(),
  };
}

String _chatLastMessagePreview(
  BuildContext context,
  Map<String, dynamic> last,
) {
  final content = (last['content'] ?? '').toString().trim();
  final type = (last['message_type'] ?? '').toString().toLowerCase();

  if (type == 'audio' ||
      content.toLowerCase() == '[voice message]') {
    return _chatText(
      context,
      'Voice message',
      ar: 'رسالة صوتية',
      ku: 'پەیامی دەنگی',
    );
  }
  if (type == 'image' || content.toLowerCase() == '[image]') {
    return _chatText(context, 'Photo', ar: 'صورة', ku: 'وێنە');
  }
  if (type == 'video' || content.toLowerCase() == '[video]') {
    return _chatText(context, 'Video', ar: 'فيديو', ku: 'ڤیدیۆ');
  }
  if (type == 'media_group' ||
      RegExp(r'^\[\d+\s+attachments?\]$', caseSensitive: false)
          .hasMatch(content)) {
    return _chatText(context, 'Media', ar: 'وسائط', ku: 'میدیا');
  }
  if (content.isEmpty) return '...';
  return content;
}

String _formatVoiceDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

bool _isAudioMessage(ChatMessage message) {
  if (message.messageType.toLowerCase() == 'audio') return true;
  if (message.attachments.length == 1 &&
      message.attachments.first.type.toLowerCase() == 'audio') {
    return true;
  }
  return false;
}


class ChatConversationPage extends StatefulWidget {
  final String carId;
  final String? receiverId;
  final String? receiverName;
  final String? carTitle;
  final String? carImageUrl;
  final String? initialDraft;
  final Map<String, dynamic>? initialListingPreview;

  const ChatConversationPage({
    super.key,
    required this.carId,
    this.receiverId,
    this.receiverName,
    this.carTitle,
    this.carImageUrl,
    this.initialDraft,
    this.initialListingPreview,
  });

  @override
  State<ChatConversationPage> createState() => _ChatConversationPageState();
}


class _ChatConversationPageState extends State<ChatConversationPage>
    with WidgetsBindingObserver {
  final List<ChatMessage> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _composerScrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<Map<String, dynamic>>? _messageUpdateSub;
  StreamSubscription<Map<String, dynamic>>? _messageDeleteSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  StreamSubscription<OutgoingChatSendEvent>? _outgoingSendSub;
  bool _isSending = false;
  bool _loadingHistory = false;
  bool _loadingOlderMessages = false;
  bool _hasMoreMessages = false;
  int _currentPage = 1;
  static const int _perPage = 50;
  Timer? _pollTimer;
  Timer? _typingDebounce;
  Timer? _scrollRetryTimer;
  bool _isTyping = false;
  String? _otherUserTypingName;
  String? _carDisplayTitle;
  String? _carImageUrl;
  Map<String, dynamic>? _listingPreview;
  Map<String, dynamic>? _fetchedCarMeta;
  bool _pendingInitialListingContext = false;

  /// Temp ids of outgoing messages the user removed or recalled before the send finished.
  final Set<String> _discardedOutgoingIds = <String>{};
  final List<XFile> _draftAttachments = <XFile>[];
  final List<ChatAttachment> _editingKeepAttachments = <ChatAttachment>[];
  ChatMessage? _replyingToMessage;
  String? _editingMessageId;
  String? _highlightMessageId;
  Timer? _highlightTimer;
  final AudioRecorder _voiceRecorder = AudioRecorder();
  bool _isRecordingVoice = false;
  Duration _voiceRecordDuration = Duration.zero;
  Timer? _voiceRecordTimer;
  String? _voiceRecordPath;

  @override
  void initState() {
    super.initState();
    _carDisplayTitle = widget.carTitle?.trim();
    _carImageUrl = resolveListingImageUrl(widget.carImageUrl);
    _listingPreview = widget.initialListingPreview == null
        ? null
        : Map<String, dynamic>.from(widget.initialListingPreview!);
    if ((_carDisplayTitle ?? '').isEmpty && _listingPreview != null) {
      final fromPreview =
          localizedListingTitle(context, _listingPreview!).trim();
      if (fromPreview.isNotEmpty) {
        _carDisplayTitle = fromPreview;
      }
    }
    if ((_carImageUrl ?? '').isEmpty && _listingPreview != null) {
      final fromPreview = listingImageUrlFromMap(_listingPreview!);
      if (fromPreview.isNotEmpty) {
        _carImageUrl = fromPreview;
      }
    }
    _pendingInitialListingContext = _listingPreview != null;
    final initialDraft = widget.initialDraft?.trim() ?? '';
    if (initialDraft.isNotEmpty) {
      _messageController.text = initialDraft;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
    }
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _setupWebSocketListeners();
    _setupTypingListener();
    _outgoingSendSub = OutgoingChatSendService.instance.events.listen(
      _onOutgoingChatSendEvent,
    );
    _loadHistory();
    _joinChat();
    _startPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollComposerToTop();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _pollNewMessages();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _typingDebounce?.cancel();
    _scrollRetryTimer?.cancel();
    _highlightTimer?.cancel();
    _voiceRecordTimer?.cancel();
    if (_isRecordingVoice) {
      unawaited(_voiceRecorder.stop());
    }
    unawaited(_voiceRecorder.dispose());
    if (_isTyping) {
      WebSocketService.sendTypingStop(widget.carId);
    }
    _messageSub?.cancel();
    _messageUpdateSub?.cancel();
    _messageDeleteSub?.cancel();
    _errorSub?.cancel();
    _typingSub?.cancel();
    _outgoingSendSub?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _composerScrollController.dispose();
    WebSocketService.leaveChat();
    super.dispose();
  }

  GlobalKey _keyForMessageId(String id) {
    return _messageKeys.putIfAbsent(id, () => GlobalKey());
  }

  @override
  Widget build(BuildContext context) {
    final mergedMeta = _mergedListingMeta();
    final localizedFromMeta = localizedListingTitle(context, mergedMeta).trim();
    final conversationTitle = localizedFromMeta.isNotEmpty
        ? localizedFromMeta
        : ((_carDisplayTitle ?? '').trim().isNotEmpty
            ? _carDisplayTitle!.trim()
            : AppLocalizations.of(context)!.listingTitle);
    return Scaffold(
            appBar: AppBar(
              centerTitle: false,
              toolbarHeight: 64,
              leading: BackButton(
                color: Theme.of(context).appBarTheme.foregroundColor,
                onPressed: () => Navigator.maybePop(context),
              ),
              title: InkWell(
                onTap: () {
                  final listingId = listingPrimaryId(_mergedListingMeta());
                  final carId = listingId.isNotEmpty
                      ? listingId
                      : widget.carId.trim();
                  if (carId.isEmpty) return;
                  Navigator.pushNamed(
                    context,
                    '/car_detail',
                    arguments: {'carId': carId},
                  );
                },
                child: Row(
                  children: [
                    buildChatListingAvatar(
                      context,
                      imageUrl: _carImageUrl,
                      radius: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AutoSizeText(
                        conversationTitle,
                        maxLines: 3,
                        minFontSize: 10,
                        stepGranularity: 0.5,
                        softWrap: true,
                        overflow: TextOverflow.clip,
                        style: Theme.of(context).appBarTheme.titleTextStyle
                                ?.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ) ??
                            const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              color: Colors.white,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (widget.receiverId != null && widget.receiverId!.isNotEmpty)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'block') _showBlockDialog();
                      if (value == 'report') _showReportDialog();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'block',
                        child: Text(
                          _chatText(
                            context,
                            'Block User',
                            ar: 'حظر المستخدم',
                            ku: 'بلۆککردنی بەکارهێنەر',
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'report',
                        child: Text(
                          _chatText(
                            context,
                            'Report User',
                            ar: 'الإبلاغ عن المستخدم',
                            ku: 'ڕاپۆرتکردنی بەکارهێنەر',
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            body: Column(
              children: [
                // Chat messages
                Expanded(
                  child: _loadingHistory && _messages.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _messages.isEmpty
                      ? Center(child: Text(_noMessagesText(context)))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount:
                              _messages.length + (_hasMoreMessages ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_hasMoreMessages && index == 0) {
                              return _loadingOlderMessages
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink();
                            }
                            final msgIndex = _hasMoreMessages
                                ? index - 1
                                : index;
                            final message = _messages[msgIndex];
                            final authService = Provider.of<AuthService>(
                              context,
                              listen: false,
                            );
                            final isMe = message.senderId == authService.userId;
                            final colorScheme = Theme.of(context).colorScheme;
                            // Peer bubbles: same treatment as home [buildGlobalCarCard].
                            final peerBubbleFill =
                                _homeListingCardBackgroundFill(context);
                            final bubbleColor = isMe
                                ? colorScheme.primary
                                : peerBubbleFill;
                            final bubbleOnStrong = isMe
                                ? Colors.white
                                : Colors.white;
                            final bubbleOnMuted = isMe
                                ? Colors.white.withValues(alpha: 0.85)
                                : Colors.white70;
                            final bubbleMaxWidth =
                                message.attachments.isNotEmpty ||
                                    _isAudioMessage(message)
                                ? 240.0
                                : message.listingPreview != null
                                ? 280.0
                                : math.min(
                                    MediaQuery.of(context).size.width * 0.58,
                                    280.0,
                                  );
                            final shrinkWrapBubble =
                                message.attachments.isEmpty &&
                                message.listingPreview == null &&
                                !_isAudioMessage(message);
                            final maxInnerWidth =
                                bubbleMaxWidth - _kBubbleHorizontalPadding;
                            final isHighlighted =
                                message.id == _highlightMessageId;
                            final shrinkInnerWidth = shrinkWrapBubble
                                ? _shrinkWrapBubbleInnerWidth(
                                    context,
                                    message: message,
                                    maxInnerWidth: maxInnerWidth,
                                    isMe: isMe,
                                    isHighlighted: isHighlighted,
                                    bubbleOnStrong: bubbleOnStrong,
                                    bubbleOnMuted: bubbleOnMuted,
                                  )
                                : null;
                            // Ensure each message has a stable key so we can jump to it from reply previews.
                            _keyForMessageId(message.id);
                            final bubbleBody = Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.stretch
                                  : CrossAxisAlignment.start,
                              children: [
                                if (message.replyToMessage != null)
                                  _buildReplyPreviewCard(
                                    context,
                                    message.replyToMessage!,
                                    isMe: true,
                                    onTap: () => _jumpToMessageId(
                                      message.replyToMessage!.id,
                                    ),
                                  ),
                                if (_isAudioMessage(message)) ...[
                                  _buildVoiceMessageBubble(
                                    context,
                                    message,
                                    iconColor: bubbleOnStrong,
                                    textColor: bubbleOnStrong,
                                    progressColor: bubbleOnStrong,
                                  ),
                                ] else if (message.attachments.isNotEmpty) ...[
                                  _buildMediaGroupBubble(
                                    context,
                                    message,
                                  ),
                                  if (!_isAttachmentPlaceholder(
                                    message.content,
                                  ))
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 6,
                                      ),
                                      child: Text(
                                        message.content,
                                        style: TextStyle(
                                          color: bubbleOnStrong,
                                        ),
                                      ),
                                    ),
                                ] else if (message.listingPreview != null) ...[
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 280,
                                    ),
                                    child: _buildListingCard(
                                      context,
                                      message.listingPreview!,
                                    ),
                                  ),
                                  if (message.content.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 8,
                                      ),
                                      child: Text(
                                        message.content,
                                        style: TextStyle(
                                          color: bubbleOnStrong,
                                        ),
                                      ),
                                    ),
                                ] else
                                  Text(
                                    _chatDisplayContent(context, message),
                                    style: TextStyle(
                                      color: bubbleOnStrong,
                                      fontStyle: message.isDeleted
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                if (isMe)
                                  Row(
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (message.editedAt != null &&
                                              !message.isDeleted)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              child: Text(
                                                _chatEditedLabel(context),
                                                style: TextStyle(
                                                  color: bubbleOnMuted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          Text(
                                            _relativeTime(
                                              context,
                                              message.createdAt,
                                            ),
                                            style: TextStyle(
                                              color: bubbleOnMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      _buildMessageStatusIndicator(
                                        context,
                                        message,
                                      ),
                                    ],
                                  )
                                else
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (message.editedAt != null &&
                                          !message.isDeleted)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: Text(
                                            _chatEditedLabel(context),
                                            style: TextStyle(
                                              color: bubbleOnMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        _relativeTime(
                                          context,
                                          message.createdAt,
                                        ),
                                        style: TextStyle(
                                          color: bubbleOnMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            );
                            final bubble = GestureDetector(
                              onLongPress: message.isDeleted
                                  ? null
                                  : () => _showMessageActions(message, isMe),
                              child: Container(
                                key: _messageKeys[message.id],
                                constraints: BoxConstraints(
                                  maxWidth: bubbleMaxWidth,
                                ),
                                margin: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: bubbleColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: isHighlighted
                                      ? Border.all(
                                          color: Colors.amberAccent,
                                          width: 2,
                                        )
                                      : !isMe
                                      ? Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.12,
                                          ),
                                          width: 1,
                                        )
                                      : null,
                                ),
                                child: shrinkInnerWidth != null
                                    ? SizedBox(
                                        width: shrinkInnerWidth,
                                        child: bubbleBody,
                                      )
                                    : bubbleBody,
                              ),
                            );
                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: bubble,
                            );
                          },
                        ),
                ),
                if (_otherUserTypingName != null &&
                    _otherUserTypingName!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_otherUserTypingName!} is typing...',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border(
                      top: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildComposerActionBanner(context),
                      if (_isRecordingVoice)
                        _buildVoiceRecordingBanner(context),
                      if (_editingMessageId != null &&
                          _editingKeepAttachments.isNotEmpty)
                        _buildEditingAttachmentsPreview(context)
                      else if (!_pendingInitialListingContext &&
                          _draftAttachments.isNotEmpty)
                        _buildDraftAttachmentsPreview(context),
                      Row(
                        children: [
                          IconButton(
                            onPressed: (_isSending ||
                                    _editingMessageId != null ||
                                    _isRecordingVoice)
                                ? null
                                : _pickAndSendMultipleMedia,
                            icon: const Icon(Icons.attach_file),
                            tooltip: _chatText(
                              context,
                              'Send attachment',
                              ar: 'إرسال مرفق',
                              ku: 'ناردنی پاشکۆ',
                            ),
                          ),
                          IconButton(
                            onPressed: (_isSending ||
                                    _editingMessageId != null ||
                                    _isRecordingVoice)
                                ? null
                                : _takePhotoAndSend,
                            icon: const Icon(Icons.camera_alt_outlined),
                            tooltip: _chatText(
                              context,
                              'Take photo',
                              ar: 'التقاط صورة',
                              ku: 'وێنە بگرە',
                            ),
                          ),
                          IconButton(
                            onPressed: (_isSending || _editingMessageId != null)
                                ? null
                                : _toggleVoiceRecording,
                            icon: Icon(
                              _isRecordingVoice ? Icons.stop_circle : Icons.mic,
                              color: _isRecordingVoice ? Colors.red : null,
                            ),
                            tooltip: _chatText(
                              context,
                              _isRecordingVoice
                                  ? 'Stop and send voice message'
                                  : 'Record voice message',
                              ar: _isRecordingVoice
                                  ? 'إيقاف وإرسال الرسالة الصوتية'
                                  : 'تسجيل رسالة صوتية',
                              ku: _isRecordingVoice
                                  ? 'وەستان و ناردنی پەیامی دەنگی'
                                  : 'تۆمارکردنی پەیامی دەنگی',
                            ),
                          ),
                          Expanded(
                            child:
                                _pendingInitialListingContext &&
                                    _listingPreview != null
                                ? Container(
                                    constraints: const BoxConstraints(
                                      maxHeight: 240,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      color: Theme.of(
                                        context,
                                      ).scaffoldBackgroundColor,
                                    ),
                                    child: Scrollbar(
                                      controller: _composerScrollController,
                                      child: SingleChildScrollView(
                                        controller: _composerScrollController,
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildListingCard(
                                              context,
                                              _listingPreview!,
                                            ),
                                            if (_draftAttachments
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 10),
                                              _buildDraftAttachmentsPreview(
                                                context,
                                              ),
                                            ],
                                            const SizedBox(height: 10),
                                            TextField(
                                              controller: _messageController,
                                              focusNode: _messageFocusNode,
                                              decoration: InputDecoration(
                                                hintText: AppLocalizations.of(
                                                  context,
                                                )!.typeMessage,
                                                isDense: true,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12,
                                                    ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: const BorderSide(
                                                    color:
                                                        _kComposerOutlineOrange,
                                                    width: 2,
                                                  ),
                                                ),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: const BorderSide(
                                                    color:
                                                        _kComposerOutlineOrange,
                                                    width: 2,
                                                  ),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: const BorderSide(
                                                    color:
                                                        _kComposerOutlineOrange,
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                              keyboardType:
                                                  TextInputType.multiline,
                                              textInputAction:
                                                  TextInputAction.newline,
                                              maxLines: null,
                                              onChanged: _onTextChanged,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                : TextField(
                                    controller: _messageController,
                                    focusNode: _messageFocusNode,
                                    decoration: InputDecoration(
                                      hintText: AppLocalizations.of(
                                        context,
                                      )!.typeMessage,
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: _kComposerOutlineOrange,
                                          width: 2,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: _kComposerOutlineOrange,
                                          width: 2,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: _kComposerOutlineOrange,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                    maxLines: null,
                                    onChanged: _onTextChanged,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: (_isSending || _isRecordingVoice)
                                ? null
                                : _sendMessage,
                            icon: const Icon(Icons.send),
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
