part of 'chat_pages.dart';

mixin _ChatConversationPageBuildBody on _ChatConversationPageBuildBodyComposer {
  Widget _buildChatConversationBody(BuildContext context) {
    return Column(
      children: [
        _buildChatMessageListArea(context),
        // Keeps the composer (text field + send button) clear of the
        // Android edge-to-edge system nav bar when the keyboard is closed,
        // matching the SafeArea(top: false, maintainBottomViewPadding: true)
        // pattern already used for other bottom bars (sell_flow.dart,
        // main_shell_navigation.dart). Only the composer is wrapped so the
        // message list above keeps using the full available height.
        SafeArea(
          top: false,
          maintainBottomViewPadding: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _buildChatComposerSection(context),
          ),
        ),
      ],
    );
  }
}
