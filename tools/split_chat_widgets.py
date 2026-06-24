"""Split chat_widgets.dart into voice, media viewer, and composer parts."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/features/chat/chat_widgets.dart"
FLOW = REPO / "lib/features/chat/chat_pages.dart"
OUT = REPO / "lib/features/chat"

lines = FILE.read_text(encoding="utf-8").splitlines()

media_start = next(i for i, line in enumerate(lines) if line.startswith("class _ChatMediaEntry"))
composer_start = next(i for i, line in enumerate(lines) if line.startswith("Widget buildChatReplyPreviewCard"))

voice_block = "\n".join(lines[2:media_start]).rstrip()
media_block = "\n".join(lines[media_start:composer_start]).rstrip()
composer_block = "\n".join(lines[composer_start:]).rstrip()

flow_lines = FLOW.read_text(encoding="utf-8").splitlines()
flow_out = []
for line in flow_lines:
    if line.strip() == "part 'chat_widgets.dart';":
        flow_out.append("part 'chat_widgets_voice.dart';")
        flow_out.append("part 'chat_widgets_media.dart';")
        flow_out.append("part 'chat_widgets_composer.dart';")
    else:
        flow_out.append(line)
FLOW.write_text("\n".join(flow_out) + "\n", encoding="utf-8")

FILE.unlink(missing_ok=True)

(OUT / "chat_widgets_voice.dart").write_text(
    "part of 'chat_pages.dart';\n\n" + voice_block + "\n",
    encoding="utf-8",
)

(OUT / "chat_widgets_media.dart").write_text(
    "part of 'chat_pages.dart';\n\n" + media_block + "\n",
    encoding="utf-8",
)

(OUT / "chat_widgets_composer.dart").write_text(
    "part of 'chat_pages.dart';\n\n" + composer_block + "\n",
    encoding="utf-8",
)

print("Split chat_widgets")
