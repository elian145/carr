"""Split chat_conversation_composer into message actions + composer UI."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CHAT = REPO / "lib/features/chat"
COMPOSER = CHAT / "chat_conversation_composer.dart"


def load_composer_body() -> list[str]:
    if COMPOSER.exists():
        lines = COMPOSER.read_text(encoding="utf-8").splitlines()
        if len(lines) > 50 and "_ChatConversationComposer" in lines[2]:
            start = 3
            end = len(lines) - 1 if lines[-1].strip() == "}" else len(lines)
            return lines[start:end]
    actions = (CHAT / "chat_conversation_message_actions.dart").read_text(encoding="utf-8")
    composer = COMPOSER.read_text(encoding="utf-8")
    a_body = re.search(
        r"mixin _ChatConversationMessageActions.*?\n(.*)\n}\s*$", actions, re.S
    )
    c_body = re.search(r"mixin _ChatConversationComposer.*?\n(.*)\n}\s*$", composer, re.S)
    if a_body and c_body:
        return (a_body.group(1) + "\n" + c_body.group(1)).splitlines()
    raw = subprocess.check_output(
        ["git", "show", "HEAD:lib/features/chat/chat_conversation_composer.dart"],
        cwd=REPO,
        text=True,
        encoding="utf-8",
    )
    lines = raw.splitlines()
    start = next(
        i for i, ln in enumerate(lines) if ln.strip().startswith("mixin _ChatConversationComposer")
    ) + 1
    end = len(lines) - 1 if lines[-1].strip() == "}" else len(lines)
    return lines[start:end]


lines = load_composer_body()
ui_start = next(
    i
    for i, ln in enumerate(lines)
    if "_buildReplyPreviewCard" in ln and ln.strip().startswith("Widget ")
)
actions_block = "\n".join(lines[:ui_start]).rstrip()
composer_block = "\n".join(lines[ui_start:]).rstrip()

(CHAT / "chat_conversation_message_actions.dart").write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationMessageActions on _ChatConversationMedia {\n"
    f"{actions_block}\n"
    "}\n",
    encoding="utf-8",
)
COMPOSER.write_text(
    "part of 'chat_pages.dart';\n\n"
    "mixin _ChatConversationComposer on _ChatConversationMessageActions {\n"
    f"{composer_block}\n"
    "}\n",
    encoding="utf-8",
)

pages = (CHAT / "chat_pages.dart").read_text(encoding="utf-8")
if "chat_conversation_message_actions.dart" not in pages:
    pages = pages.replace(
        "part 'chat_conversation_composer.dart';",
        "part 'chat_conversation_message_actions.dart';\n"
        "part 'chat_conversation_composer.dart';",
    )
(CHAT / "chat_pages.dart").write_text(pages, encoding="utf-8")

print("actions", len(actions_block.splitlines()), "composer", len(composer_block.splitlines()))
