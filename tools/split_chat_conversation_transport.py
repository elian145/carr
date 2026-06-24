"""Split chat_conversation_transport.dart into sync, paging, listing, media, and realtime mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/features/chat/chat_conversation_transport.dart"
PAGES = REPO / "lib/features/chat/chat_pages.dart"
PAGE = REPO / "lib/features/chat/chat_conversation_page.dart"
OUT = REPO / "lib/features/chat"

lines = FILE.read_text(encoding="utf-8").splitlines()

paging_start = next(i for i, line in enumerate(lines) if line.strip().startswith("void _onScroll()"))
listing_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Map<String, dynamic> _mergedListingMeta()"))
media_start = next(i for i, line in enumerate(lines) if line.strip().startswith("void _mergeInFlightMediaPending()"))
realtime_start = next(i for i, line in enumerate(lines) if line.strip().startswith("void _setupWebSocketListeners()"))

sync_block = "\n".join(lines[3:paging_start]).rstrip()
paging_block = "\n".join(lines[paging_start:listing_start]).rstrip()
listing_block = "\n".join(lines[listing_start:media_start]).rstrip()
media_block = "\n".join(lines[media_start:realtime_start]).rstrip()
realtime_block = "\n".join(lines[realtime_start:-1]).rstrip()

parts = [
    ("chat_conversation_transport_sync.dart", "_ChatConversationTransportSync", "_ChatConversationTransportStore", sync_block),
    ("chat_conversation_transport_listing.dart", "_ChatConversationTransportListing", "_ChatConversationTransportSync", listing_block),
    ("chat_conversation_transport_media.dart", "_ChatConversationTransportMedia", "_ChatConversationTransportListing", media_block),
    ("chat_conversation_transport_paging.dart", "_ChatConversationTransportPaging", "_ChatConversationTransportMedia", paging_block),
    ("chat_conversation_transport_realtime.dart", "_ChatConversationTransportRealtime", "_ChatConversationTransportPaging", realtime_block),
]

for filename, mixin_name, on_name, body in parts:
    (OUT / filename).write_text(
        "part of 'chat_pages.dart';\n\n"
        f"mixin {mixin_name} on {on_name} {{\n"
        f"{body}\n"
        "}\n",
        encoding="utf-8",
    )

(FILE).write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationTransport on _ChatConversationTransportRealtime {}\n",
    encoding="utf-8",
)

pages = PAGES.read_text(encoding="utf-8")
for filename, _, _, _ in parts:
    part = f"part '{filename}';\n"
    if part not in pages:
        pages = pages.replace(
            "part 'chat_conversation_transport.dart';\n",
            part + "part 'chat_conversation_transport.dart';\n",
        )
PAGES.write_text(pages, encoding="utf-8")

page = PAGE.read_text(encoding="utf-8")
if "_ChatConversationTransportSync" not in page:
    page = page.replace(
        "        _ChatConversationTransportStore,\n"
        "        _ChatConversationTransport,\n",
        "        _ChatConversationTransportStore,\n"
        "        _ChatConversationTransportSync,\n"
        "        _ChatConversationTransportListing,\n"
        "        _ChatConversationTransportMedia,\n"
        "        _ChatConversationTransportPaging,\n"
        "        _ChatConversationTransportRealtime,\n"
        "        _ChatConversationTransport,\n",
    )
PAGE.write_text(page, encoding="utf-8")

print("Split chat_conversation_transport into", len(parts), "mixins")
