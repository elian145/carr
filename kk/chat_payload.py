"""N-1: shared chat payload limits and trusted listing-preview derivation.

One place for every chat send path (REST JSON ``/send``, REST multipart
``/send_*`` and the Socket.IO ``send_message`` event) so the limits cannot
drift apart again, and so a ``listing_preview`` is *never* copied from client
input: only a listing id is read from the client, and the stored/returned
preview is built from the Car row itself.
"""

from __future__ import annotations

import json
import math
from typing import Any

# ---------------------------------------------------------------------------
# Limits (shared by REST JSON, REST multipart and Socket.IO).
# ---------------------------------------------------------------------------
MAX_CHAT_CONTENT_CHARS = 4000
# The client-supplied ``listing_preview`` only needs an id. Older app builds also
# send display fields (incl. the whole image gallery), which are ignored but must
# still fit; anything bigger is refused.
MAX_LISTING_PREVIEW_INPUT_BYTES = 16 * 1024
# 4000 chars may be 16 KB of UTF-8, plus ids and a 16 KB preview: whole JSON body / socket
# event cap (text-only; attachments travel as multipart and have their own
# per-file caps in kk/routes/chat.py).
MAX_CHAT_JSON_BODY_BYTES = 64 * 1024
MAX_CHAT_SOCKET_PAYLOAD_BYTES = 64 * 1024
MAX_CHAT_ID_CHARS = 128

# Clamps for the server-derived preview fields.
_MAX_TITLE = 200
_MAX_SHORT = 100

_PREVIEW_ID_KEYS = ("id", "listing_id", "listingId", "car_id", "carId")

ERR_PAYLOAD_TOO_LARGE = "payload_too_large"
ERR_CONTENT_TOO_LONG = "content_too_long"
ERR_INVALID_PREVIEW = "invalid_listing_preview"
ERR_PREVIEW_UNAVAILABLE = "listing_preview_unavailable"


class ChatPayloadError(Exception):
    """A client payload violates a chat limit / rule.

    ``body()`` is the consistent error shape used by every transport:
    ``{"message": ..., "code": ...}`` (REST JSON body / Socket.IO ``error``
    event argument); ``status`` is the HTTP status for REST callers.
    """

    def __init__(self, message: str, code: str, status: int = 400, **extra: Any):
        super().__init__(message)
        self.message = message
        self.code = code
        self.status = status
        self.extra = extra

    def body(self) -> dict:
        out = {"message": self.message, "code": self.code}
        out.update(self.extra)
        return out


def _too_large(what: str, max_bytes: int) -> ChatPayloadError:
    return ChatPayloadError(
        f"{what} too large", ERR_PAYLOAD_TOO_LARGE, 413, max_bytes=max_bytes
    )


def _preview_unavailable() -> ChatPayloadError:
    # Identical for unknown / deleted / draft / hidden / foreign-private so the
    # existence of a private listing is never revealed.
    return ChatPayloadError(
        "Listing preview not available", ERR_PREVIEW_UNAVAILABLE, 404
    )


# ---------------------------------------------------------------------------
# Size checks
# ---------------------------------------------------------------------------
def _json_size(value: Any) -> int:
    try:
        return len(json.dumps(value, ensure_ascii=False, default=str).encode("utf-8"))
    except Exception:
        return MAX_CHAT_SOCKET_PAYLOAD_BYTES + 1


def check_content(content: str) -> None:
    if len(content) > MAX_CHAT_CONTENT_CHARS:
        raise ChatPayloadError("content too long", ERR_CONTENT_TOO_LONG, 400)


def check_json_body_size(content_length: int | None, raw_len: int | None = None) -> None:
    """REST JSON: reject a body above the chat cap (declared or actual)."""
    for n in (content_length, raw_len):
        if n is not None and n > MAX_CHAT_JSON_BODY_BYTES:
            raise _too_large("Request body", MAX_CHAT_JSON_BODY_BYTES)


def check_socket_payload_size(payload: Any) -> None:
    if _json_size(payload) > MAX_CHAT_SOCKET_PAYLOAD_BYTES:
        raise _too_large("Message payload", MAX_CHAT_SOCKET_PAYLOAD_BYTES)


def parse_preview_form_field(raw: str | None) -> Any:
    """Multipart ``listing_preview`` form field -> parsed JSON (or None)."""
    raw = (raw or "").strip()
    if not raw:
        return None
    if len(raw.encode("utf-8")) > MAX_LISTING_PREVIEW_INPUT_BYTES:
        raise _too_large("listing_preview", MAX_LISTING_PREVIEW_INPUT_BYTES)
    try:
        return json.loads(raw)
    except Exception:
        raise ChatPayloadError(
            "listing_preview must be a JSON object", ERR_INVALID_PREVIEW, 400
        )


def check_multipart_text(form) -> None:
    """Multipart text fields (caption, preview) -- before any upload work."""
    check_content((form.get("content") or "").strip())
    for key in ("receiver_id", "receiverId", "reply_to_message_id", "replyToMessageId"):
        if len(form.get(key) or "") > MAX_CHAT_ID_CHARS:
            raise ChatPayloadError(f"{key} too long", "invalid_field", 400)


# ---------------------------------------------------------------------------
# Trusted preview derivation
# ---------------------------------------------------------------------------
def _clamp(value: Any, limit: int) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    return text[:limit]


def _own_image_ref(car) -> str | None:
    """Primary photo of THIS listing, from its stored media rows only."""
    from .routes.chat import _first_car_image_rel_path

    ref = _first_car_image_rel_path(car)
    return _clamp(ref, 2048)


def build_listing_preview(car) -> dict:
    """The only preview shape that is ever stored or returned for a listing."""
    price = None
    try:
        if car.price is not None:
            price = float(car.price)
            if not math.isfinite(price):
                price = None
    except Exception:
        price = None
    title = _clamp(getattr(car, "title", None), _MAX_TITLE)
    if not title:
        title = _clamp(
            " ".join(
                str(p)
                for p in (getattr(car, "brand", None), getattr(car, "model", None), getattr(car, "year", None))
                if p
            ),
            _MAX_TITLE,
        )
    preview = {
        "id": car.public_id,
        "title": title,
        "brand": _clamp(getattr(car, "brand", None), _MAX_SHORT),
        "model": _clamp(getattr(car, "model", None), _MAX_SHORT),
        "trim": _clamp(getattr(car, "trim", None), _MAX_SHORT),
        "year": getattr(car, "year", None),
        "price": price,
        "currency": _clamp(getattr(car, "currency", None), 3),
        "location": _clamp(getattr(car, "location", None), _MAX_SHORT),
        "image_url": _own_image_ref(car),
    }
    return {k: v for k, v in preview.items() if v is not None}


def _listing_usable(car, *viewers) -> bool:
    """Active, real (not a revision working copy) and visible to every viewer."""
    from .listing_visibility import listing_visible_to_viewer, not_a_working_copy

    if car is None or not_a_working_copy(car) is None:
        return False
    if not getattr(car, "is_active", False):
        return False
    return all(listing_visible_to_viewer(car, v) for v in viewers)


def _requested_listing_id(raw_preview: dict) -> str | None:
    for key in _PREVIEW_ID_KEYS:
        if key not in raw_preview:
            continue
        value = raw_preview[key]
        if value is None or value == "":
            continue
        if isinstance(value, bool) or not isinstance(value, (str, int)):
            raise ChatPayloadError(
                "listing_preview id must be a string", ERR_INVALID_PREVIEW, 400
            )
        text = str(value).strip()
        if len(text) > MAX_CHAT_ID_CHARS:
            raise ChatPayloadError(
                "listing_preview id too long", ERR_INVALID_PREVIEW, 400
            )
        return text or None
    return None


def resolve_listing_preview(raw_preview: Any, *, me, receiver, conversation_car) -> dict | None:
    """Server-derived preview for a send request, or ``None`` if none asked.

    Only the listing id is taken from ``raw_preview`` (default: the listing the
    conversation is about). Every other client field is ignored. Raises
    :class:`ChatPayloadError` for oversized / malformed input and for an
    unknown / inactive / not-visible listing.
    """
    if raw_preview is None:
        return None
    if not isinstance(raw_preview, dict):
        raise ChatPayloadError(
            "listing_preview must be a JSON object", ERR_INVALID_PREVIEW, 400
        )
    if not raw_preview:
        return None
    if _json_size(raw_preview) > MAX_LISTING_PREVIEW_INPUT_BYTES:
        raise _too_large("listing_preview", MAX_LISTING_PREVIEW_INPUT_BYTES)

    wanted = _requested_listing_id(raw_preview)
    car = conversation_car
    if wanted and wanted not in (str(conversation_car.public_id), str(conversation_car.id)):
        from .chat_realtime import resolve_car_for_chat

        car = resolve_car_for_chat(wanted)
    if not _listing_usable(car, me, receiver):
        raise _preview_unavailable()
    return build_listing_preview(car)


def sanitize_stored_listing_preview(stored: Any, car) -> dict | None:
    """Read-side defence for rows written before N-1 (and as defence in depth).

    The stored JSON is never trusted: when the message's own listing still
    exists and is public the preview is re-derived from it; otherwise it is
    dropped (legacy forged titles/prices/external image URLs cannot be told
    apart from real ones).
    """
    if not stored or not isinstance(stored, dict):
        return None
    if car is None:
        return None
    from .listing_visibility import listing_is_public, not_a_working_copy

    try:
        if not_a_working_copy(car) is None or not getattr(car, "is_active", False):
            return None
        if not listing_is_public(car):
            return None
        return build_listing_preview(car)
    except Exception:
        return None
