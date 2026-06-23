"""Split chat_conversation_send into media + composer mixins."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CHAT = REPO / "lib/features/chat"
SEND = CHAT / "chat_conversation_send.dart"


def load_send_body() -> list[str]:
    if SEND.exists():
        lines = SEND.read_text(encoding="utf-8").splitlines()
        if len(lines) > 50 and "_ChatConversationSend" in lines[2]:
            start = 3
            end = len(lines) - 1 if lines[-1].strip() == "}" else len(lines)
            return lines[start:end]
    media = (CHAT / "chat_conversation_media.dart").read_text(encoding="utf-8")
    composer = (CHAT / "chat_conversation_composer.dart").read_text(encoding="utf-8")
    m_body = re.search(r"mixin _ChatConversationMedia.*?\n(.*)\n}\s*$", media, re.S)
    c_body = re.search(r"mixin _ChatConversationComposer.*?\n(.*)\n}\s*$", composer, re.S)
    if m_body and c_body:
        return (m_body.group(1) + "\n" + c_body.group(1)).splitlines()
    raw = subprocess.check_output(
        ["git", "show", "HEAD:lib/features/chat/chat_conversation_send.dart"],
        cwd=REPO,
        text=True,
        encoding="utf-8",
    )
    lines = raw.splitlines()
    start = next(
        i for i, ln in enumerate(lines) if ln.strip().startswith("mixin _ChatConversationSend")
    ) + 1
    end = len(lines) - 1 if lines[-1].strip() == "}" else len(lines)
    return lines[start:end]


lines = load_send_body()
composer_start = next(
    i
    for i, ln in enumerate(lines)
    if "_canEditMessage" in ln and ln.strip().startswith("bool ")
)
media_block = "\n".join(lines[:composer_start]).rstrip()
composer_block = "\n".join(lines[composer_start:]).rstrip()

(CHAT / "chat_conversation_media.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationMedia on _ChatConversationTransport {\n"
    f"{media_block}\n"
    "}\n",
    encoding="utf-8",
)
(CHAT / "chat_conversation_composer.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationComposer on _ChatConversationMedia {\n"
    f"{composer_block}\n"
    "}\n",
    encoding="utf-8",
)
SEND.write_text(
    "part of 'chat_pages.dart';\n\n"
    "// Media and composer logic live in chat_conversation_media.dart "
    "and chat_conversation_composer.dart.\n",
    encoding="utf-8",
)

pages = (CHAT / "chat_pages.dart").read_text(encoding="utf-8")
for part in ("chat_conversation_media.dart", "chat_conversation_composer.dart"):
    if f"part '{part}'" not in pages:
        pages = pages.replace(
            "part 'chat_conversation_send.dart';",
            f"part '{part}';\npart 'chat_conversation_send.dart';",
        )
(CHAT / "chat_pages.dart").write_text(pages, encoding="utf-8")

print(
    "media",
    len(media_block.splitlines()),
    "composer",
    len(composer_block.splitlines()),
)
