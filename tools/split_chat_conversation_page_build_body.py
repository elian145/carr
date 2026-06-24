"""Split chat_conversation_page_build_body.dart into message list and composer mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PAGES = REPO / "lib/features/chat/chat_pages.dart"
PAGE = REPO / "lib/features/chat/chat_conversation_page.dart"
BODY = REPO / "lib/features/chat/chat_conversation_page_build_body.dart"
OUT = REPO / "lib/features/chat"

lines = BODY.read_text(encoding="utf-8").splitlines()
expanded_start = next(
    i for i, line in enumerate(lines) if line.strip().startswith("Expanded(")
)
composer_start = next(
    i for i, line in enumerate(lines) if line.strip().startswith("if (_otherUserTypingName")
)
expanded_close = composer_start - 1
while expanded_close > expanded_start and not lines[expanded_close].strip().endswith("),"):
    expanded_close -= 1
column_children_close = next(
    i
    for i in range(len(lines) - 1, composer_start, -1)
    if lines[i].strip() == "],"
    and lines[i].startswith("              ")
)

msg_lines = lines[expanded_start : expanded_close + 1]
if msg_lines[-1].strip().endswith("),"):
    msg_lines[-1] = msg_lines[-1].rstrip()[:-2] + ");"
messages_block = "    return " + "\n".join(msg_lines).lstrip()
composer_block = "\n".join(lines[composer_start:column_children_close]).rstrip()

(BODY).write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationPageBuildBody on _ChatConversationPageBuildBodyComposer {\n"
    "  Widget _buildChatConversationBody(BuildContext context) {\n"
    "    return Column(\n"
    "      children: [\n"
    "        _buildChatMessageListArea(context),\n"
    "        ..._buildChatComposerSection(context),\n"
    "      ],\n"
    "    );\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "chat_conversation_page_build_body_messages.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationPageBuildBodyMessages on _ChatConversationPageLifecycle {\n"
    "  Widget _buildChatMessageListArea(BuildContext context) {\n"
    + messages_block
    + "\n  }\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "chat_conversation_page_build_body_composer.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationPageBuildBodyComposer on _ChatConversationPageBuildBodyMessages {\n"
    "  List<Widget> _buildChatComposerSection(BuildContext context) {\n"
    "    return [\n"
    + composer_block
    + "\n    ];\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

pages = PAGES.read_text(encoding="utf-8")
if "chat_conversation_page_build_body_messages.dart" not in pages:
    pages = pages.replace(
        "part 'chat_conversation_page_build_body.dart';\n",
        "part 'chat_conversation_page_build_body_messages.dart';\n"
        "part 'chat_conversation_page_build_body_composer.dart';\n"
        "part 'chat_conversation_page_build_body.dart';\n",
    )
    PAGES.write_text(pages, encoding="utf-8")

page = PAGE.read_text(encoding="utf-8")
if "_ChatConversationPageBuildBodyMessages" not in page:
    page = page.replace(
        "        _ChatConversationPageBuildBody,\n",
        "        _ChatConversationPageBuildBodyMessages,\n"
        "        _ChatConversationPageBuildBodyComposer,\n"
        "        _ChatConversationPageBuildBody,\n",
    )
    PAGE.write_text(page, encoding="utf-8")

print("Split chat_conversation_page_build_body")
