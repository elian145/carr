"""Canonical newline handling for every file this pipeline writes (JSON / JSONL / Markdown).

The committed raw/ and generated/ artifacts are CRLF (see .gitattributes: `-text`, so git never re-translates them) and
build_overlay.py records sha256 of those exact bytes. Writing with Path.write_text() uses the *platform* newline, so a Linux
regeneration would emit LF and differ from the committed bytes. Everything is therefore written through this module:
text is normalised to "\n" first and then emitted with an explicit CRLF, on every OS.

Reading is unaffected (json.load / read_text accept both).
"""
from __future__ import annotations

from pathlib import Path

NEWLINE = "\r\n"


def canonical_bytes(text: str) -> bytes:
    """UTF-8 bytes of `text` with every line ending (LF, CRLF or bare CR) written as CRLF."""
    return text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", NEWLINE).encode("utf-8")


def write_text_canonical(path, text: str) -> None:
    """Write `text` to `path` as UTF-8 with explicit CRLF newlines, independent of the platform."""
    Path(path).write_bytes(canonical_bytes(text))
