"""Split chat_conversation_page.dart into lifecycle and build mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PAGE = REPO / "lib/features/chat/chat_conversation_page.dart"
PAGES = REPO / "lib/features/chat/chat_pages.dart"
OUT = REPO / "lib/features/chat"

lines = PAGE.read_text(encoding="utf-8").splitlines()

widget_end = next(i for i, line in enumerate(lines) if line.startswith("class _ChatConversationPageState"))
lifecycle_start = next(i for i, line in enumerate(lines) if line.strip() == "void initState() {")
build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)

# Include @override before initState if present.
if lifecycle_start > 0 and lines[lifecycle_start - 1].strip() == "@override":
    lifecycle_start -= 1

widget_block = "\n".join(
    line for line in lines[:widget_end]
    if not line.strip().startswith("part of")
).rstrip()
state_header = lines[widget_end].rstrip()
mixins_line = lines[widget_end + 1].rstrip() if widget_end + 1 < len(lines) else ""

lifecycle_block = "\n".join(lines[lifecycle_start:build_start]).rstrip()
build_block = "\n".join(lines[build_start:-1]).rstrip()

new_mixins = mixins_line.replace(
    "_ChatConversationMessageUi, WidgetsBindingObserver",
    "_ChatConversationMessageUi, _ChatConversationPageLifecycle, "
    "_ChatConversationPageBuild, WidgetsBindingObserver",
)

(OUT / "chat_conversation_page_lifecycle.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationPageLifecycle on _ChatConversationMessageUi {\n"
    f"{lifecycle_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "chat_conversation_page_build.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationPageBuild on _ChatConversationPageLifecycle {\n"
    f"{build_block}\n"
    "}\n",
    encoding="utf-8",
)

(PAGE).write_text(
    "part of 'chat_pages.dart';\n\n"
    f"{widget_block}\n\n"
    f"{state_header}\n"
    f"    {new_mixins} {{\n"
    "}\n",
    encoding="utf-8",
)

pages = PAGES.read_text(encoding="utf-8")
if "chat_conversation_page_lifecycle.dart" not in pages:
    pages = pages.replace(
        "part 'chat_conversation_page.dart';\n",
        "part 'chat_conversation_page_lifecycle.dart';\n"
        "part 'chat_conversation_page_build.dart';\n"
        "part 'chat_conversation_page.dart';\n",
    )
    PAGES.write_text(pages, encoding="utf-8")

print("lifecycle", len(lifecycle_block.splitlines()), "build", len(build_block.splitlines()))
