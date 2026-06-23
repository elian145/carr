"""Split chat transport into store helpers + sync/events mixin."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TRANSPORT = REPO / "lib/features/chat/chat_conversation_transport.dart"
PAGES = REPO / "lib/features/chat/chat_pages.dart"
PAGE = REPO / "lib/features/chat/chat_conversation_page.dart"
OUT = REPO / "lib/features/chat"

lines = TRANSPORT.read_text(encoding="utf-8").splitlines()


def find(substr: str, start: int = 0) -> int:
    for i in range(start, len(lines)):
        if substr in lines[i]:
            return i
    raise ValueError(substr)


sync_start = find("void _setupTypingListener()")
store_start = find("void _addMessageIfMissing(ChatMessage message)")
listing_start = find("Map<String, dynamic> _mergedListingMeta()")
scroll_start = find("void _scrollToBottom({bool jump = false})")

sync_block = "\n".join(lines[sync_start:store_start]).rstrip()
store_block = "\n".join(
    lines[store_start:listing_start] + [""] + lines[scroll_start:-1]
).rstrip()
listing_block = "\n".join(lines[listing_start:scroll_start]).rstrip()

(OUT / "chat_conversation_transport_store.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationTransportStore on _ChatConversationFields {\n"
    f"{store_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "chat_conversation_transport.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationTransport on _ChatConversationTransportStore {\n"
    f"{sync_block}\n\n"
    f"{listing_block}\n"
    "}\n",
    encoding="utf-8",
)

pages = PAGES.read_text(encoding="utf-8")
if "chat_conversation_transport_store.dart" not in pages:
    pages = pages.replace(
        "part 'chat_conversation_transport.dart';\n",
        "part 'chat_conversation_transport_store.dart';\n"
        "part 'chat_conversation_transport.dart';\n",
    )
    PAGES.write_text(pages, encoding="utf-8")

page = PAGE.read_text(encoding="utf-8")
page = page.replace(
    "_ChatConversationTransport, _ChatConversationMedia",
    "_ChatConversationTransportStore, _ChatConversationTransport, _ChatConversationMedia",
)
PAGE.write_text(page, encoding="utf-8")

print(
    "store",
    len(store_block.splitlines()),
    "transport",
    len(sync_block.splitlines()) + len(listing_block.splitlines()),
)
