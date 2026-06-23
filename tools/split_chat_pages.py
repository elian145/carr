"""Split lib/features/chat/chat_pages.dart — shared helpers, widgets, list, notifications."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SRC = REPO / "lib/features/chat/chat_pages.dart"
OUT = REPO / "lib/features/chat"
lines = SRC.read_text(encoding="utf-8").splitlines()


def find_line(prefix: str, start: int = 0) -> int:
    for i in range(start, len(lines)):
        if lines[i].startswith(prefix):
            return i
    raise ValueError(f"not found: {prefix!r}")


import_end = 0
while import_end < len(lines) and (
    lines[import_end].startswith("import ") or lines[import_end].strip() == ""
):
    import_end += 1

voice_line = find_line("class _ChatVoiceBubble")
list_line = find_line("class ChatListPage")
conv_line = find_line("class ChatConversationPage")
notif_line = find_line("class NotificationsPage")

parts = [
    ("chat_shared.dart", import_end, voice_line),
    ("chat_widgets.dart", voice_line, list_line),
    ("chat_list_page.dart", list_line, conv_line),
    ("chat_notifications_page.dart", notif_line, len(lines)),
]

part_lines: list[str] = []
for fname, start, end in parts:
    body = "\n".join(lines[start:end])
    (OUT / fname).write_text(f"part of 'chat_pages.dart';\n\n{body}\n", encoding="utf-8")
    part_lines.append(f"part '{fname}';")
    print(f"wrote {fname}: {end - start} lines")

header = "\n".join(lines[:import_end])
conversation_block = "\n".join(lines[conv_line:notif_line])

main = f"""{header}
{chr(10).join(part_lines)}

{conversation_block}
"""

SRC.write_text(main + "\n", encoding="utf-8")
print(f"main shell: {len(main.splitlines())} lines")
