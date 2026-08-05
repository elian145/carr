/// Chat feature library (part / mixin map — M-15).
///
/// Entry: import this file for chat list / conversation pages.
///
/// Live transport (P-10): Socket.IO is primary while connected; REST history
/// polling runs only as a fallback when the socket is down — see
/// `chat_live_transport.dart`.
///
/// Leaf widgets (real libraries under widgets/, not parts):
/// - chat_theme.dart / chat_strings.dart — colors + copy helpers
/// - widgets/chat_voice_bubble.dart — ChatVoiceBubble
/// - widgets/chat_media_viewer.dart — ChatMediaEntry, showChatMediaDialog
/// - widgets/chat_composer_widgets.dart — reply/composer previews
///
/// Conversation mixin chain (`_ChatConversationPageState with …`):
/// Fields → TransportStore → Sync → Listing → Media → Paging → Realtime →
/// Transport → MediaActions → MessageActions → Composer → MessageUiNav →
/// MessageUi → Lifecycle → BuildBodyMessages → BuildBodyComposer →
/// BuildBody → Build
///
/// Edit guide:
/// - list UI → chat_list_page.dart
/// - send / composer → chat_conversation_composer.dart, chat_conversation_send.dart
/// - message bubbles → chat_conversation_message_ui.dart
/// - socket / history → chat_conversation_transport_*.dart
///
/// State stays Provider-based; Riverpod migration is deferred.
library;

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/websocket_service.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../services/outgoing_chat_send_service.dart';
import '../../services/feature_flags.dart';
import '../../shared/errors/user_error_text.dart';
import '../../shared/ui/responsive.dart';
import '../../shared/auth/phone_verification_gate.dart';
import '../../shared/listings/listing_identity.dart';
import '../../shared/media/media_url.dart';
import '../../shared/text/pretty_title_case.dart';
import '../../data/car_name_translations.dart';
import '../../widgets/theme_toggle_widget.dart';
import '../../shared/debug/app_log.dart';
import '../../app/widgets/listing_network_image.dart';
import '../../shared/ui/listing_feed_skeleton.dart';
import '../../shared/ui/empty_state_panel.dart';
import '../../app/widgets/main_shell_navigation.dart' show navigateMainShellTab;
import '../../shared/trust/report_dialog.dart';
import 'chat_live_transport.dart';
import 'chat_strings.dart';
import 'chat_theme.dart';
import 'widgets/chat_composer_widgets.dart';
import 'widgets/chat_media_viewer.dart';
import 'widgets/chat_voice_bubble.dart';
import '../../shared/ui/app_haptics.dart';

part 'chat_shared.dart';
part 'chat_list_page.dart';
part 'chat_notifications_page.dart';
part 'chat_conversation_fields.dart';
part 'chat_conversation_transport_store.dart';
part 'chat_conversation_transport_sync.dart';
part 'chat_conversation_transport_listing.dart';
part 'chat_conversation_transport_media.dart';
part 'chat_conversation_transport_paging.dart';
part 'chat_conversation_transport_realtime.dart';
part 'chat_conversation_transport.dart';
part 'chat_conversation_media.dart';
part 'chat_conversation_message_actions.dart';
part 'chat_conversation_composer.dart';
part 'chat_conversation_send.dart';
part 'chat_conversation_actions.dart';
part 'chat_conversation_message_ui_nav.dart';
part 'chat_conversation_message_ui.dart';
part 'chat_conversation_page_lifecycle.dart';
part 'chat_conversation_page_build_body_messages.dart';
part 'chat_conversation_page_build_body_composer.dart';
part 'chat_conversation_page_build_body.dart';
part 'chat_conversation_page_build.dart';
part 'chat_conversation_page.dart';
