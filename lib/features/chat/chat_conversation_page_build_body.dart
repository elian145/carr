part of 'chat_pages.dart';

mixin _ChatConversationPageBuildBody on _ChatConversationPageBuildBodyComposer {
  Widget _buildChatConversationBody(BuildContext context) {
    return Column(
      children: [
        _buildChatMessageListArea(context),
        ..._buildChatComposerSection(context),
      ],
    );
  }
}
