part of 'chat_pages.dart';


class ChatConversationPage extends StatefulWidget {
  final String carId;
  final String? receiverId;
  final String? receiverName;
  final String? carTitle;
  final String? carImageUrl;
  final String? initialDraft;
  final Map<String, dynamic>? initialListingPreview;
  // Whether `initialListingPreview` should also prefill the composer with a
  // ready-to-send listing card (the "contact seller / interested in this
  // listing" flow). Callers that only supply `initialListingPreview` for
  // display metadata (e.g. ChatListPage's cached car title/image, see
  // commit fb05e85) must leave this false so the composer stays a normal
  // empty text field. Defaults to false so existing/other conversations
  // never unexpectedly show a listing attachment ready to send.
  final bool prefillComposerWithListing;

  const ChatConversationPage({
    super.key,
    required this.carId,
    this.receiverId,
    this.receiverName,
    this.carTitle,
    this.carImageUrl,
    this.initialDraft,
    this.initialListingPreview,
    this.prefillComposerWithListing = false,
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
        _ChatConversationPageBuildBodyMessages,
        _ChatConversationPageBuildBodyComposer,
        _ChatConversationPageBuildBody,
        _ChatConversationPageBuild {}
