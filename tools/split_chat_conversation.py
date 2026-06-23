"""Move ChatConversationPage into its own part file."""
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
chat = REPO / "lib/features/chat/chat_pages.dart"
lines = chat.read_text(encoding="utf-8").splitlines()

conv_start = next(
    i for i, line in enumerate(lines) if line.startswith("class ChatConversationPage")
)

import_end = 0
while import_end < len(lines) and (
    lines[import_end].startswith("import ") or lines[import_end].strip() == ""
):
    import_end += 1

part_directives = [ln for ln in lines[import_end:] if ln.startswith("part ")]

conv_body = "\n".join(lines[conv_start:])
(chat.parent / "chat_conversation_page.dart").write_text(
    f"part of 'chat_pages.dart';\n\n{conv_body}\n",
    encoding="utf-8",
)

parts_block = "\n".join(part_directives + ["part 'chat_conversation_page.dart';"])
header = "\n".join(lines[:import_end])
chat.write_text(f"{header}\n{parts_block}\n", encoding="utf-8")
print(f"chat_pages.dart shell: {len(parts_block.splitlines()) + import_end} lines")
print(f"chat_conversation_page.dart: {len(conv_body.splitlines())} lines")
