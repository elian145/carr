"""What is being moderated: resolution, eligibility, content token, facts.

Two kinds of subject, both already part of the manual moderation flow:

``listing``   a NEW listing awaiting approval (``Car.status == 'pending'``,
              still ``is_active``).
``revision``  a seller's SUBMITTED edit of an already-published listing
              (``CarRevision.status == 'pending'``). Drafts (``editing`` /
              ``editing_legacy``) and rejected edits are never eligible --
              unfinished editing drafts are never approved.

Every function here only reads.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import timedelta
from typing import Any

from .. import listing_revisions as lr
from ..models import (
    Car,
    CarImage,
    CarMediaItem,
    CarRevision,
    CarVideo,
    ListingModerationEvent,
    ListingModerationRun,
    ListingReport,
    User,
    UserReport,
    db,
)
from ..time_utils import utcnow
from .rules import Facts, normalize_text


class Ineligible(Exception):
    """The subject is not (or no longer) something automation may touch."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


@dataclass
class Subject:
    type: str  # listing | revision
    key: str
    car: Car  # the listing (approved row for a revision)
    target: Car  # the row whose content is judged (car, or the working copy)
    token: str
    revision: CarRevision | None = None


def subject_key(subject_type: str, subject_id: int) -> str:
    return f"{subject_type}:{int(subject_id)}"


def listing_content_token(car: Car) -> str:
    """Hash of everything that would become public for a NEW listing, plus
    the moderation-relevant state. Changes when the seller edits any field,
    the gallery, or a media item changes state (an upload finishing counts)."""
    items = CarMediaItem.query.filter_by(car_id=car.id).all()
    payload = {
        "fields": {f: lr._norm(getattr(car, f, None)) for f in lr.PROPOSABLE_FIELDS},
        "images": lr._image_signature(car.id),
        "videos": lr._video_signature(car.id),
        "items": sorted([[it.client_media_id, it.status] for it in items]),
        "media_status": car.media_status,
        "status": (car.status or "").strip().lower(),
        "is_active": bool(car.is_active),
    }
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:40]


def resolve_subject(subject_type: str, subject_id: int) -> Subject:
    """Load the subject and verify it is eligible RIGHT NOW. Raises
    ``Ineligible`` with a stable code otherwise."""
    if subject_type == "listing":
        car = db.session.get(Car, int(subject_id))
        if car is None:
            raise Ineligible("not_found")
        if lr.is_working_copy(car):
            raise Ineligible("working_copy")
        if not car.is_active:
            raise Ineligible("deleted_or_inactive")
        if (car.status or "").strip().lower() != "pending":
            raise Ineligible("not_pending")
        return Subject(
            "listing", subject_key("listing", car.id), car, car, listing_content_token(car)
        )
    if subject_type == "revision":
        rev = db.session.get(CarRevision, int(subject_id))
        if rev is None:
            raise Ineligible("not_found")
        if rev.status != lr.REVISION_PENDING:
            # editing / editing_legacy drafts and rejected edits: never.
            raise Ineligible("not_pending")
        car = db.session.get(Car, rev.car_id)
        if car is None or not lr.listing_is_published(car):
            raise Ineligible("listing_not_published")
        shadow = lr.get_working_copy(rev)
        if shadow is None:
            raise Ineligible("revision_gone")
        return Subject(
            "revision",
            subject_key("revision", rev.id),
            car,
            shadow,
            lr.revision_content_token(rev, shadow),
            rev,
        )
    raise Ineligible("unknown_subject_type")


def subject_for_car_id(car_id: int) -> tuple[str, int] | None:
    """Map any car row id (a listing, or the hidden working copy a media job
    is writing to) to its moderation subject, if it currently has one."""
    car = db.session.get(Car, int(car_id))
    if car is None:
        return None
    if lr.is_working_copy(car):
        rev = lr.get_revision_for_working_copy(car)
        if rev is not None and rev.status == lr.REVISION_PENDING:
            return "revision", rev.id
        return None
    if car.is_active and (car.status or "").strip().lower() == "pending":
        return "listing", car.id
    return None


# ---------------------------------------------------------------------------
# Facts
# ---------------------------------------------------------------------------


def _num(v):
    try:
        return float(v) if v is not None else None
    except (TypeError, ValueError):
        return None


def _fields(car: Car) -> dict[str, Any]:
    return {
        "title": car.title,
        "brand": car.brand,
        "model": car.model,
        "year": car.year,
        "mileage": car.mileage,
        "price": _num(car.price),
        "currency": car.currency,
        "location": car.location,
        "condition": car.condition,
        "engine_type": car.engine_type,
        "transmission": car.transmission,
        "drive_type": car.drive_type,
        "body_type": car.body_type,
        "vin": car.vin,
        "description": car.description,
    }


def _media(target: Car) -> dict[str, Any]:
    items = CarMediaItem.query.filter_by(car_id=target.id).all()
    images = lr._image_rows(target.id)
    return {
        "media_status": target.media_status,
        "in_flight": sum(1 for i in items if i.status in ("awaiting_upload", "processing")),
        "failed": sum(1 for i in items if i.status == "failed"),
        "items": [
            {
                "client_media_id": i.client_media_id,
                "kind": i.kind,
                "status": i.status,
                "is_cover": bool(i.is_cover),
            }
            for i in items
        ],
        "images": [
            {
                "url": im.image_url,
                "kind": im.kind,
                "is_primary": bool(im.is_primary),
                "source_media_id": im.source_media_id,
                "width": im.image_width,
                "height": im.image_height,
            }
            for im in images
        ],
        "video_count": CarVideo.query.filter_by(car_id=target.id).count(),
    }


def _pinned_manual(car_id: int) -> bool:
    last = (
        ListingModerationEvent.query.filter(
            ListingModerationEvent.car_id == car_id,
            ListingModerationEvent.event_type.in_(("manual_only_pinned", "manual_only_cleared")),
        )
        .order_by(ListingModerationEvent.id.desc())
        .first()
    )
    return bool(last and last.event_type == "manual_only_pinned")


def _seller(subject: Subject, settings: dict) -> dict[str, Any]:
    car = subject.car
    user = db.session.get(User, car.seller_id) if car.seller_id else None
    if user is None:
        return {"exists": False}
    auto_published = (
        db.session.query(ListingModerationRun.car_id)
        .filter(
            ListingModerationRun.subject_type == "listing",
            ListingModerationRun.outcome == "published",
            ListingModerationRun.car_id.isnot(None),
        )
        .subquery()
    )
    seller_car_ids = [
        r[0] for r in db.session.query(Car.id).filter(Car.seller_id == user.id).all()
    ]
    # Trust is earned from listings a HUMAN approved: automation's own
    # approvals never count (no self-reinforcing loop). For a pending edit the
    # edited listing itself is one of the seller's approved listings; for a new
    # listing, of course, it is not counted.
    prior_q = Car.query.filter(
        Car.seller_id == user.id,
        Car.is_active.is_(True),
        Car.status.in_(("active", "sold")),
        ~Car.id.in_(db.session.query(auto_published.c.car_id)),
    )
    if subject.type == "listing":
        prior_q = prior_q.filter(Car.id != car.id)
    prior_approved = prior_q.count()
    open_reports = 0
    if seller_car_ids:
        open_reports += ListingReport.query.filter(
            ListingReport.car_id.in_(seller_car_ids), ListingReport.status == "pending"
        ).count()
    open_reports += UserReport.query.filter(
        UserReport.reported_id == user.id, UserReport.status == "pending"
    ).count()
    admin_rejections = ListingModerationRun.query.filter(
        ListingModerationRun.seller_id == user.id,
        ListingModerationRun.admin_outcome.in_(("rejected", "hidden", "deleted")),
    ).count()
    hidden = Car.query.filter(Car.seller_id == user.id, Car.status == "hidden").count()
    return {
        "exists": True,
        "active": bool(user.is_active),
        "phone_verified": bool(getattr(user, "phone_verified", False)),
        "dealer_approved": (user.dealer_status or "none") == "approved",
        "prior_approved": prior_approved,
        "open_reports": open_reports,
        "admin_rejections": admin_rejections,
        "hidden_listings": hidden,
        "manual_only": _pinned_manual(car.id),
    }


def _duplicates(subject: Subject) -> dict[str, Any]:
    car, target = subject.car, subject.target
    exclude = [car.id, target.id]
    q = Car.query.filter(
        Car.seller_id == car.seller_id,
        ~Car.id.in_(exclude),
        Car.status.in_(("pending", "active", "sold")),
        Car.is_active.is_(True),
    )
    own = q.all()
    similar = sum(
        1
        for c in own
        if (c.brand, c.model, c.year, c.mileage, _num(c.price), c.location)
        == (target.brand, target.model, target.year, target.mileage, _num(target.price), target.location)
    )
    mine = normalize_text(target.description)
    same_desc = 0
    if len(mine) >= 40:
        same_desc = sum(1 for c in own if normalize_text(c.description) == mine)
    vin = (target.vin or "").strip().upper()
    vin_own = vin_other = 0
    if vin:
        for c in Car.query.filter(
            db.func.upper(Car.vin) == vin,
            ~Car.id.in_(exclude),
            Car.status.in_(("pending", "active", "sold")),
            Car.is_active.is_(True),
        ).all():
            if c.seller_id == car.seller_id:
                vin_own += 1
            else:
                vin_other += 1
    cutoff = utcnow() - timedelta(hours=24)
    recent = Car.query.filter(
        Car.seller_id == car.seller_id,
        Car.created_at >= cutoff,
        Car.status != "revision",
    ).count()
    return {
        "own_similar": similar,
        "own_same_description": same_desc,
        "vin_own": vin_own,
        "vin_other_seller": vin_other,
        "recent_24h": recent,
    }


def _revision_facts(subject: Subject) -> dict[str, Any]:
    car, shadow = subject.car, subject.target
    changed = lr.revision_changed_fields(car, shadow)
    media = lr.working_copy_media_state(shadow)
    return {
        "changed_fields": changed,
        "old_price": _num(car.price),
        "new_price": _num(shadow.price),
        "new_media": media["total"] > 0,
    }


def build_facts(subject: Subject, settings: dict) -> Facts:
    return Facts(
        subject_type=subject.type,
        fields=_fields(subject.target),
        media=_media(subject.target),
        seller=_seller(subject, settings),
        duplicates=_duplicates(subject),
        revision=_revision_facts(subject) if subject.type == "revision" else None,
    )


def ai_inputs(subject: Subject, facts: Facts) -> tuple[str, str, list[str], bool]:
    """(title, description, image urls, needed). For a revision only new
    content needs the provider: unchanged text and photos were already
    approved. New photos are sent first."""
    target = subject.target
    urls = [
        i["url"]
        for i in facts.media["images"]
        if i.get("url") and (i.get("kind") or "listing") != "damage"
    ]
    cover = [i["url"] for i in facts.media["images"] if i.get("is_primary") and i.get("url")]
    ordered = list(dict.fromkeys(cover + urls))
    needed = True
    if subject.type == "revision":
        approved_urls = {
            i.image_url for i in CarImage.query.filter_by(car_id=subject.car.id).all()
        }
        new_urls = [u for u in ordered if u not in approved_urls]
        rest = [u for u in ordered if u in approved_urls]
        ordered = new_urls + rest
        text_changed = (subject.car.description or "") != (target.description or "")
        needed = bool(new_urls) or text_changed
        if not new_urls:
            ordered = []
    return target.title or "", target.description or "", ordered, needed
