part of 'chat_pages.dart';


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

class _ChatConversationPageState extends _ChatConversationFields
    with
        _ChatConversationTransportStore,
        _ChatConversationTransportSync,
        _ChatConversationTransportListing,
        _ChatConversationTransportMedia,
        _ChatConversationTransportPaging,
        _ChatConversationTransportRealtime,
        _ChatConversationTransport,
        _ChatConversationMedia,
        _ChatConversationMessageActions,
        _ChatConversationComposer,
        _ChatConversationMessageUiNav,
        _ChatConversationMessageUi,
        WidgetsBindingObserver,
        _ChatConversationPageLifecycle,
        _ChatConversationPageBuild {}
