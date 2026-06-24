"""Split chat_conversation_page_build.dart into shell and body mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/features/chat/chat_conversation_page_build.dart"
PAGES = REPO / "lib/features/chat/chat_pages.dart"
PAGE = REPO / "lib/features/chat/chat_conversation_page.dart"
OUT = REPO / "lib/features/chat"

lines = FILE.read_text(encoding="utf-8").splitlines()

build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

body_line = next(i for i, line in enumerate(lines) if line.strip().startswith("body: Column("))
column_close = next(
    i
    for i in range(body_line + 1, len(lines))
    if lines[i].rstrip() == "            )," and lines[i + 1].strip() == ");"
)
column_start = body_line + 1

body_block = "\n".join(
    ["      return Column("] + lines[column_start:column_close] + ["      );"]
).rstrip()

shell_lines = lines[build_start:body_line]
shell_block = "\n".join(shell_lines).rstrip()
shell_block += "\n            body: _buildChatConversationBody(context),\n    );\n  }"

(OUT / "chat_conversation_page_build_body.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationPageBuildBody on _ChatConversationPageLifecycle {\n"
    "  Widget _buildChatConversationBody(BuildContext context) {\n"
    f"{body_block}\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(FILE).write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationPageBuild on _ChatConversationPageBuildBody {\n"
    f"{shell_block}\n"
    "}\n",
    encoding="utf-8",
)

pages = PAGES.read_text(encoding="utf-8")
part = "part 'chat_conversation_page_build_body.dart';\n"
if part not in pages:
    pages = pages.replace(
        "part 'chat_conversation_page_build.dart';\n",
        part + "part 'chat_conversation_page_build.dart';\n",
    )
    PAGES.write_text(pages, encoding="utf-8")

page = PAGE.read_text(encoding="utf-8")
if "_ChatConversationPageBuildBody" not in page:
    page = page.replace(
        "        _ChatConversationPageBuild {}",
        "        _ChatConversationPageBuildBody,\n        _ChatConversationPageBuild {}",
    )
    PAGE.write_text(page, encoding="utf-8")

print("Split chat_conversation_page_build")
