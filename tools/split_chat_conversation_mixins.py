"""Split chat_conversation_page.dart into fields + action/ui mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CONV = REPO / "lib/features/chat/chat_conversation_page.dart"
CHAT = REPO / "lib/features/chat/chat_pages.dart"
lines = CONV.read_text(encoding="utf-8").splitlines()


def find_line(substr: str, start: int = 0) -> int:
    for i in range(start, len(lines)):
        if substr in lines[i]:
            return i
    raise ValueError(substr)


widget_line = find_line("class ChatConversationPage")
state_line = find_line("class _ChatConversationPageState")
fields_start = find_line("final List<ChatMessage> _messages = [];")
init_override = find_line("@override", fields_start)
typing_line = find_line("void _setupTypingListener() {", init_override)
lifecycle_override = find_line("@override", typing_line)
post_lifecycle = find_line("void _addMessageIfMissing", lifecycle_override)
dispose_override = find_line("@override", post_lifecycle)
key_line = find_line("GlobalKey _keyForMessageId", dispose_override)
ui_start = find_line("void _flashHighlight", key_line)
build_override = find_line("@override", ui_start)

fields_block = "\n".join(lines[fields_start:init_override])
init_block = "\n".join(lines[init_override:typing_line])
lifecycle_block = "\n".join(lines[lifecycle_override:post_lifecycle])
actions_raw = "\n".join(lines[typing_line:lifecycle_override] + lines[post_lifecycle:dispose_override])
actions_block = actions_raw.replace("_perPage", "_ChatConversationFields._perPage")
dispose_block = "\n".join(lines[dispose_override:key_line])
key_block = "\n".join(lines[key_line:ui_start])
ui_block = "\n".join(lines[ui_start:build_override])
build_block = "\n".join(lines[build_override:-1])  # drop final class closing brace
build_block = build_block.replace("_perPage", "_ChatConversationFields._perPage")

widget_block = "\n".join(lines[widget_line:state_line])
out = REPO / "lib/features/chat"

(out / "chat_conversation_fields.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "abstract class _ChatConversationFields extends State<ChatConversationPage> {\n"
    f"{fields_block}\n"
    "}\n",
    encoding="utf-8",
)

(out / "chat_conversation_actions.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationActions on _ChatConversationFields {\n"
    f"{actions_block}\n"
    "}\n",
    encoding="utf-8",
)

(out / "chat_conversation_message_ui.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationMessageUi on _ChatConversationActions {\n"
    f"{ui_block}\n"
    "}\n",
    encoding="utf-8",
)

shell = (
    "part of 'chat_pages.dart';\n\n"
    f"{widget_block}\n"
    "class _ChatConversationPageState extends _ChatConversationFields\n"
    "    with _ChatConversationActions, _ChatConversationMessageUi, WidgetsBindingObserver {\n"
    f"{init_block}\n"
    f"{lifecycle_block}\n"
    f"{dispose_block}\n"
    f"{key_block}\n"
    f"{build_block}\n"
    "}\n"
)
CONV.write_text(shell, encoding="utf-8")

chat_text = CHAT.read_text(encoding="utf-8")
if "chat_conversation_fields.dart" not in chat_text:
    chat_text = chat_text.replace(
        "part 'chat_conversation_page.dart';",
        "part 'chat_conversation_fields.dart';\n"
        "part 'chat_conversation_actions.dart';\n"
        "part 'chat_conversation_message_ui.dart';\n"
        "part 'chat_conversation_page.dart';",
    )
    CHAT.write_text(chat_text, encoding="utf-8")

print("ok")
