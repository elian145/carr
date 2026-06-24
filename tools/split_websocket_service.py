"""Split websocket_service.dart into common helpers, service impl, and chat models."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/services/websocket_service.dart"
OUT = REPO / "lib/services"

lines = FILE.read_text(encoding="utf-8").splitlines()

first_decl = next(
    i
    for i, line in enumerate(lines)
    if line.strip() and not line.startswith("import ") and not line.startswith("//")
)
service_start = next(i for i, line in enumerate(lines) if line.startswith("class WebSocketService"))
models_start = next(i for i, line in enumerate(lines) if line.startswith("class ChatAttachment"))

imports = "\n".join(lines[:first_decl]).rstrip()
common_block = "\n".join(lines[first_decl:service_start]).rstrip()
impl_block = "\n".join(lines[service_start:models_start]).rstrip()
models_block = "\n".join(lines[models_start:]).rstrip()

(FILE).write_text(
    imports
    + "\n\n"
    + "part 'websocket_service_common.dart';\n"
    + "part 'websocket_service_impl.dart';\n"
    + "part 'websocket_service_models.dart';\n",
    encoding="utf-8",
)

(OUT / "websocket_service_common.dart").write_text(
    "part of 'websocket_service.dart';\n\n" + common_block + "\n",
    encoding="utf-8",
)

(OUT / "websocket_service_impl.dart").write_text(
    "part of 'websocket_service.dart';\n\n" + impl_block + "\n",
    encoding="utf-8",
)

(OUT / "websocket_service_models.dart").write_text(
    "part of 'websocket_service.dart';\n\n" + models_block + "\n",
    encoding="utf-8",
)

print("Split websocket_service")
