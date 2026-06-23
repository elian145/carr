"""Split chat_conversation_actions into transport + send mixins."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ACTIONS = REPO / "lib/features/chat/chat_conversation_actions.dart"
CHAT = REPO / "lib/features/chat"


def method_end(lines: list[str], start: int) -> int:
    depth = 0
    opened = False
    for i in range(start, len(lines)):
        for ch in lines[i]:
            if ch == "{":
                depth += 1
                opened = True
            elif ch == "}":
                depth -= 1
                if opened and depth == 0:
                    return i + 1
    raise ValueError(f"method end not found from line {start + 1}")


def load_actions_body() -> list[str]:
    raw = subprocess.check_output(
        ["git", "show", "HEAD:lib/features/chat/chat_conversation_actions.dart"],
        cwd=REPO,
        text=True,
        encoding="utf-8",
    )
    lines = raw.splitlines()
    if len(lines) < 50:
        transport = (CHAT / "chat_conversation_transport.dart").read_text(encoding="utf-8")
        send = (CHAT / "chat_conversation_send.dart").read_text(encoding="utf-8")
        t_body = re.search(
            r"mixin _ChatConversationTransport.*?\n(.*)\n}\s*$", transport, re.S
        )
        s_body = re.search(r"mixin _ChatConversationSend.*?\n(.*)\n}\s*$", send, re.S)
        if t_body and s_body:
            return (t_body.group(1) + "\n" + s_body.group(1)).splitlines()
        raise RuntimeError("Could not load chat conversation actions source")
    start = 3
    if not lines[2].strip().startswith("mixin _ChatConversationActions"):
        start = next(
            i
            for i, ln in enumerate(lines)
            if ln.strip().startswith("mixin _ChatConversationActions")
        ) + 1
    end = len(lines)
    if lines[-1].strip() == "}":
        end -= 1
    return lines[start:end]


def normalize_media_helpers(text: str) -> str:
    return text.replace("_isImageFile(", "_chatIsImageFile(").replace(
        "_isVideoFile(", "_chatIsVideoFile("
    )


lines = load_actions_body()

media_start = next(
    i for i, ln in enumerate(lines) if "_isImageFile" in ln and ln.strip().startswith("bool ")
)
video_start = next(
    i for i, ln in enumerate(lines) if "_isVideoFile" in ln and ln.strip().startswith("bool ")
)
send_start = method_end(lines, video_start)

transport_block = normalize_media_helpers("\n".join(lines[:media_start]).rstrip())
send_block = normalize_media_helpers("\n".join(lines[send_start:]).rstrip())

(CHAT / "chat_conversation_transport.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationTransport on _ChatConversationFields {\n"
    f"{transport_block}\n"
    "}\n",
    encoding="utf-8",
)
(CHAT / "chat_conversation_send.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationSend on _ChatConversationTransport {\n"
    f"{send_block}\n"
    "}\n",
    encoding="utf-8",
)
ACTIONS.write_text(
    "part of 'chat_pages.dart';\n\n"
    "// Transport and send logic live in chat_conversation_transport.dart "
    "and chat_conversation_send.dart.\n",
    encoding="utf-8",
)
print(
    "transport",
    len(transport_block.splitlines()),
    "send",
    len(send_block.splitlines()),
)
