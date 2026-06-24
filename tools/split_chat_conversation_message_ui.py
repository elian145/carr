"""Split chat_conversation_message_ui.dart into nav helpers and bubble widgets."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
UI = REPO / "lib/features/chat/chat_conversation_message_ui.dart"
PAGES = REPO / "lib/features/chat/chat_pages.dart"
PAGE = REPO / "lib/features/chat/chat_conversation_page.dart"
OUT = REPO / "lib/features/chat"

lines = UI.read_text(encoding="utf-8").splitlines()

nav_start = 3  # after mixin header line
widgets_start = next(
    i for i, line in enumerate(lines) if line.strip().startswith("String _listingTitle")
)

nav_block = "\n".join(lines[nav_start:widgets_start]).rstrip()
widgets_block = "\n".join(lines[widgets_start:-1]).rstrip()

(OUT / "chat_conversation_message_ui_nav.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationMessageUiNav on _ChatConversationComposer {\n"
    f"{nav_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "chat_conversation_message_ui.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationMessageUi on _ChatConversationMessageUiNav {\n"
    f"{widgets_block}\n"
    "}\n",
    encoding="utf-8",
)

pages = PAGES.read_text(encoding="utf-8")
if "chat_conversation_message_ui_nav.dart" not in pages:
    pages = pages.replace(
        "part 'chat_conversation_message_ui.dart';\n",
        "part 'chat_conversation_message_ui_nav.dart';\n"
        "part 'chat_conversation_message_ui.dart';\n",
    )
    PAGES.write_text(pages, encoding="utf-8")

page = PAGE.read_text(encoding="utf-8")
page = page.replace(
    "_ChatConversationComposer, _ChatConversationMessageUi, WidgetsBindingObserver",
    "_ChatConversationComposer, _ChatConversationMessageUiNav, "
    "_ChatConversationMessageUi, WidgetsBindingObserver",
)
PAGE.write_text(page, encoding="utf-8")

print("nav", len(nav_block.splitlines()), "widgets", len(widgets_block.splitlines()))
