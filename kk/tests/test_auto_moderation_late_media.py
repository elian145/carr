"""Photos / videos changed AFTER a listing was evaluated.

The media endpoints (``kk/routes/media.py``) change the content a moderation
decision is about without touching the listing row, so they used to leave no
trace for moderation. Pins the contract of the fix:

* every committed media change re-checks the listing / submitted edit (one
  debounced, idempotent job) -- attach, delete, cover, layout, videos;
* nothing is judged while declared uploads are still processing;
* the same content never costs a second evaluation, an AI call is reused for an
  identical question, and a burst of changes costs one evaluation;
* a decision made for older content can never be applied to newer content;
* published listings keep going through the revision workflow;
* the sweep's bounded content-token backstop finds whatever a lost trigger missed;
* shadow mode never publishes and the rules-first AI skip is untouched.
"""

from __future__ import annotations

import uuid

import pytest

# Shared fixtures / builders (a real Flask app + SQLite, a recording AI stub).
from kk.tests.test_auto_moderation_engine import (  # noqa: F401
    _CDN,
    _add_damage_photos,
    _ai_ok_for,
    _auth,
    _car,
    _car_state,
    _live,
    _login,
    _moderate,
    _photo_verdicts,
    _published_car,
    _quiesce,
    _revision,
    _runs,
    _set_ai,
    _trusted_seller,
    _user,
    app,
    app_ctx,
    clean,
    client,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _no_storage_io(monkeypatch):
    """Deleting a photo also deletes its storage object (best effort); never
    reach for real storage from a test."""
    import kk.routes.media as media

    monkeypatch.setattr(media, "_delete_media_storage_object", lambda url: None)


def _seller(app, client):
    """A trusted seller (one earlier approved listing) plus a login token."""
    uid, username = _trusted_seller(app)
    return uid, _login(client, username)


def _owned_url(app, uid, not_car_id):
    """A photo URL the seller already owns on ANOTHER listing -- the only kind
    of https URL the attach endpoint accepts from a seller."""
    from kk.models import Car, CarImage

    with app.app_context():
        row = (
            CarImage.query.join(Car, Car.id == CarImage.car_id)
            .filter(Car.seller_id == uid, Car.id != not_car_id)
            .order_by(CarImage.id)
            .first()
        )
        return row.image_url


def _attach(client, token, public_id, urls, kind="listing"):
    return client.post(
        f"/api/cars/{public_id}/images/attach", json={"urls": urls, "kind": kind}, headers=_auth(token)
    )


def _jobs(enqueued):
    """(subject type, subject id, countdown) of every moderation job enqueued."""
    return [
        (k["args"][0], k["args"][1], k.get("countdown")) for kind, k in enqueued if kind == "job"
    ]


def _run_job(app, stype, sid):
    return _moderate(app, stype, sid)


def _tokens(app, car_id):
    return [r["token"] for r in _runs(app, car_id)]


def _ai_texts(calls):
    return [u for c in calls for u in c["urls"]]


def _debounce():
    from kk.auto_moderation.triggers import MEDIA_CHANGE_DEBOUNCE_SECONDS

    return MEDIA_CHANGE_DEBOUNCE_SECONDS


# ---------------------------------------------------------------------------
# 1. Late photos trigger a re-evaluation
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("kind", ["damage", "listing"])
def test_late_photo_triggers_a_reevaluation_that_inspects_it(app, client, clean, kind):
    calls = []
    _set_ai(calls=calls)
    uid, token = _seller(app, client)
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "shadow_would_approve"
    assert len(calls) == 1 and len(calls[0]["urls"]) == 3
    clean.clear()

    url = _owned_url(app, uid, c["car_id"])
    r = _attach(client, token, c["public_id"], [url], kind)
    assert r.status_code == 201, r.data
    # one delayed job for this exact listing -- nothing was judged inline
    assert _jobs(clean) == [("listing", c["car_id"], _debounce())]
    assert len(_runs(app, c["car_id"])) == 1

    assert _run_job(app, "listing", c["car_id"])["outcome"] == "shadow_would_approve"
    runs = _runs(app, c["car_id"])
    assert len(runs) == 2 and runs[0]["token"] != runs[1]["token"]
    assert len(calls) == 2 and url in calls[1]["urls"]  # the new photo really reached the AI


def test_unrelated_late_damage_photo_is_sent_to_manual_review(app, client, clean, monkeypatch):
    """The production miss: an unrelated photo added to Damaged Parts after the
    listing was evaluated. Live mode, so a missed check would have published."""
    from kk.auto_moderation import engine

    uid, token = _seller(app, client)
    c = _car(app, uid)
    url = _owned_url(app, uid, c["car_id"])
    suffix = url.rsplit("/", 1)[1]
    _set_ai(calls=[], overrides={1: lambda urls: _photo_verdicts(urls, not_car=(suffix,))})
    _live(monkeypatch, app)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c["car_id"])
    assert _runs(app, c["car_id"])[0]["outcome"] == "pending_apply"  # old decision, not yet applied
    monkeypatch.setattr(engine, "_apply", real_apply)
    clean.clear()

    assert _attach(client, token, c["public_id"], [url], "damage").status_code == 201
    assert _jobs(clean) == [("listing", c["car_id"], _debounce())]
    old_run = _runs(app, c["car_id"])[0]
    # the old approval can no longer be applied to the changed gallery ...
    with app.app_context():
        assert real_apply(old_run["id"], "listing", c["car_id"])["outcome"] == "stale"
    assert _car_state(app, c["car_id"])["status"] == "pending"
    # ... and the new content is judged: a human looks at it
    out = _run_job(app, "listing", c["car_id"])
    assert out["decision"] == "NEEDS_REVIEW" and out["outcome"] == "queued_for_review"
    assert "ai_flagged" in _runs(app, c["car_id"])[-1]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"


# ---------------------------------------------------------------------------
# 2. Every media-changing endpoint re-checks
# ---------------------------------------------------------------------------


def _add_video(app, car_id):
    from kk.models import CarVideo, db

    with app.app_context():
        v = CarVideo(car_id=car_id, video_url=f"{_CDN.replace('car_photos', 'car_videos')}/{car_id}.mp4")
        db.session.add(v)
        db.session.commit()
        return v.id


def _call(client, token, c, action, app):
    pid = c["public_id"]
    h = _auth(token)
    if action == "primary":
        url = f"{_CDN}/{c['car_id']}_1.jpg"
        return client.put(f"/api/cars/{pid}/images/primary", json={"image_url": url}, headers=h)
    if action == "layout":
        rows = [{"id": i, "order": n, "focus_y": 0.25 if n == 0 else 0.5} for n, i in enumerate(c["image_ids"])]
        return client.put(f"/api/cars/{pid}/images/layout", json={"images": rows}, headers=h)
    if action == "delete_image":
        return client.delete(f"/api/cars/{pid}/images/{c['image_ids'][2]}", headers=h)
    if action == "delete_video":
        vid = _add_video(app, c["car_id"])
        return client.delete(f"/api/cars/{pid}/videos/{vid}", headers=h)
    raise AssertionError(action)


@pytest.mark.parametrize("action", ["primary", "layout", "delete_image", "delete_video"])
def test_every_media_endpoint_requests_one_delayed_recheck(app, client, clean, action):
    _set_ai(calls=[])
    uid, token = _seller(app, client)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    clean.clear()
    r = _call(client, token, c, action, app)
    assert r.status_code in (200, 201), r.data
    assert _jobs(clean) == [("listing", c["car_id"], _debounce())]


def test_replacing_a_photo_invalidates_the_old_decision(app, client, clean, monkeypatch):
    """Replacement = delete + attach: both change the token, the last job judges
    the final gallery and the old approval is never applied."""
    from kk.auto_moderation import engine

    calls = []
    _set_ai(calls=calls)
    uid, token = _seller(app, client)
    c = _car(app, uid)
    photo_a = _owned_url(app, uid, c["car_id"])
    photo_b = f"{_CDN}/{c['car_id']}_replacement.jpg"
    from kk.models import Car, CarImage, db

    with app.app_context():  # a second photo the seller owns on another of their listings
        other = CarImage.query.filter_by(image_url=photo_a).first().car_id
        db.session.add(CarImage(car_id=other, image_url=photo_b, kind="listing", order=9))
        db.session.commit()
    assert _attach(client, token, c["public_id"], [photo_a], "damage").status_code == 201
    _live(monkeypatch, app)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c["car_id"])  # decided for the gallery WITH photo A, not yet applied
    monkeypatch.setattr(engine, "_apply", real_apply)
    old = _runs(app, c["car_id"])[0]
    assert old["outcome"] == "pending_apply" and photo_a in calls[-1]["urls"]
    clean.clear()

    with app.app_context():
        photo_a_id = CarImage.query.filter_by(car_id=c["car_id"], image_url=photo_a).one().id
    assert client.delete(f"/api/cars/{c['public_id']}/images/{photo_a_id}", headers=_auth(token)).status_code == 200
    assert _attach(client, token, c["public_id"], [photo_b], "damage").status_code == 201
    assert len(_jobs(clean)) == 2 and {j[:2] for j in _jobs(clean)} == {("listing", c["car_id"])}

    with app.app_context():
        assert real_apply(old["id"], "listing", c["car_id"])["outcome"] == "stale"
    assert _car_state(app, c["car_id"])["status"] == "pending"
    out = _run_job(app, "listing", c["car_id"])
    assert out["outcome"] == "published"  # the NEW gallery was judged on its merits and passed
    assert photo_b in calls[-1]["urls"] and photo_a not in calls[-1]["urls"]


def test_deleting_the_offending_photo_is_judged_again(app, client, clean):
    """A listing flagged for a late photo is judged again once the seller
    removes it (and adds a good one): the old objection no longer applies."""
    uid, token = _seller(app, client)
    c = _car(app, uid)
    bad = _owned_url(app, uid, c["car_id"])
    suffix = bad.rsplit("/", 1)[1]
    calls = []
    _set_ai(calls=calls, overrides={1: lambda urls: _photo_verdicts(urls, not_car=(suffix,))})
    _moderate(app, "listing", c["car_id"])
    assert _attach(client, token, c["public_id"], [bad], "damage").status_code == 201
    assert _run_job(app, "listing", c["car_id"])["decision"] == "NEEDS_REVIEW"
    clean.clear()

    from kk.models import CarImage, db

    with app.app_context():
        bad_id = CarImage.query.filter_by(car_id=c["car_id"], image_url=bad).one().id
        other = CarImage.query.filter(CarImage.image_url == bad, CarImage.car_id != c["car_id"]).first().car_id
        good = f"{_CDN}/{c['car_id']}_good.jpg"
        db.session.add(CarImage(car_id=other, image_url=good, kind="listing", order=9))
        db.session.commit()
    assert client.delete(f"/api/cars/{c['public_id']}/images/{bad_id}", headers=_auth(token)).status_code == 200
    assert _attach(client, token, c["public_id"], [good], "damage").status_code == 201
    assert len(_jobs(clean)) == 2
    out = _run_job(app, "listing", c["car_id"])
    assert out["decision"] == "AUTO_APPROVE" and out["outcome"] == "shadow_would_approve"
    assert good in calls[-1]["urls"] and bad not in calls[-1]["urls"]


def test_deleting_a_declared_photo_is_never_waved_through(app, client, clean):
    """Deleting a photo the listing DECLARED at creation leaves its manifest item
    without a photo; that existing protection still sends the listing to a human."""
    _set_ai(calls=[])
    uid, token = _seller(app, client)
    c = _car(app, uid)
    assert client.delete(
        f"/api/cars/{c['public_id']}/images/{c['image_ids'][2]}", headers=_auth(token)
    ).status_code == 200
    out = _run_job(app, "listing", c["car_id"])
    assert out["decision"] == "NEEDS_REVIEW" and "media_missing" in _runs(app, c["car_id"])[-1]["codes"]


# ---------------------------------------------------------------------------
# 3. Protections that must keep working
# ---------------------------------------------------------------------------


def test_no_recheck_while_uploads_are_still_processing(app, client, clean):
    """Unfinished uploads are never judged; the upload finishing triggers it."""
    uid, token = _seller(app, client)
    c = _car(app, uid, media="processing")
    url = _owned_url(app, uid, c["car_id"])
    assert _attach(client, token, c["public_id"], [url], "damage").status_code == 201
    assert _jobs(clean) == []
    assert _runs(app, c["car_id"]) == []


def test_direct_trigger_is_inert_when_nothing_is_eligible(app, clean):
    from kk.auto_moderation.triggers import request_moderation_after_media_change as req

    uid, _ = _trusted_seller(app)
    active = _car(app, uid, status="active", price=1)  # published: no subject of its own
    hidden = _car(app, uid, status="hidden", price=2)
    editing = _published_car(app, uid, price=3)
    _rid, shadow_id, _p = _revision(app, editing["car_id"], status="editing", description="Work in progress, not yet sent.")
    pending = _car(app, uid, price=4)
    with app.app_context():
        assert req(active["car_id"]) is False and req(hidden["car_id"]) is False
        assert req(None) is False and req(10**9) is False
        assert req(shadow_id) is False  # a draft edit is never moderated
        assert _jobs(clean) == []
        assert req(pending["car_id"]) is True
    assert _jobs(clean) == [("listing", pending["car_id"], _debounce())]


def test_mode_off_requests_nothing(app, client, clean):
    from kk.tests.test_auto_moderation_engine import _settings

    uid, token = _seller(app, client)
    c = _car(app, uid)
    _settings(app, mode="off")
    assert _attach(client, token, c["public_id"], [_owned_url(app, uid, c["car_id"])]).status_code == 201
    assert _jobs(clean) == []


def test_unchanged_content_causes_no_duplicate_evaluation_or_ai_call(app, client, clean):
    calls = []
    _set_ai(calls=calls)
    uid, token = _seller(app, client)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    clean.clear()
    # same layout / cover / re-attach of a photo that is already there
    assert client.put(
        f"/api/cars/{c['public_id']}/images/primary", json={"image_url": f"{_CDN}/{c['car_id']}_0.jpg"},
        headers=_auth(token),
    ).status_code == 200
    assert _attach(client, token, c["public_id"], [f"{_CDN}/{c['car_id']}_1.jpg"]).status_code == 201
    jobs = _jobs(clean)
    assert jobs and all(j[:2] == ("listing", c["car_id"]) for j in jobs)
    for _ in jobs:
        assert _run_job(app, "listing", c["car_id"])["outcome"] == "done"
    assert len(_runs(app, c["car_id"])) == 1 and len(calls) == 1


def test_burst_of_photo_changes_costs_one_evaluation(app, client, clean):
    calls = []
    _set_ai(calls=calls)
    uid, token = _seller(app, client)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    assert len(calls) == 1
    clean.clear()
    urls = [f"{_CDN}/{c['car_id']}_x{i}.jpg" for i in range(3)]
    # the seller's own staged uploads: owned URLs on another listing of theirs
    from kk.models import CarImage, db

    with app.app_context():
        other = _owned_url(app, uid, c["car_id"])
        from kk.models import Car

        other_car = CarImage.query.filter_by(image_url=other).first().car_id
        for u in urls:
            db.session.add(CarImage(car_id=other_car, image_url=u, kind="listing", order=9))
        db.session.commit()
    for u in urls:
        assert _attach(client, token, c["public_id"], [u], "damage").status_code == 201
    jobs = _jobs(clean)
    assert len(jobs) == 3 and {j[2] for j in jobs} == {_debounce()}  # delayed, so they land after the burst
    results = [_run_job(app, "listing", c["car_id"])["outcome"] for _ in jobs]
    assert results == ["shadow_would_approve", "done", "done"]
    assert len(_runs(app, c["car_id"])) == 2  # ONE extra evaluation, for the final gallery
    # ... whose 6 photos went out in 2 provider requests (batches of 4), not 3 evaluations' worth
    assert len(calls) == 1 + 2 and set(urls) <= set(_ai_texts(calls[1:]))


def test_cover_crop_change_reuses_the_ai_answer_and_costs_no_call(app, client, clean):
    """A new content token the provider can't see (a crop) re-records the
    decision for the new token but asks the provider nothing."""
    calls = []
    _set_ai(calls=calls)
    uid, token = _seller(app, client)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    assert len(calls) == 1
    clean.clear()
    rows = [{"id": i, "order": n, "focus_y": 0.9} for n, i in enumerate(c["image_ids"])]
    assert client.put(
        f"/api/cars/{c['public_id']}/images/layout", json={"images": rows}, headers=_auth(token)
    ).status_code == 200
    out = _run_job(app, "listing", c["car_id"])
    assert out["outcome"] == "shadow_would_approve"
    assert len(_runs(app, c["car_id"])) == 2 and len(calls) == 1  # no second provider request
    from kk.models import ListingModerationRun

    with app.app_context():
        last = ListingModerationRun.query.filter_by(car_id=c["car_id"]).order_by(ListingModerationRun.id.desc()).first()
        first = ListingModerationRun.query.filter_by(car_id=c["car_id"]).order_by(ListingModerationRun.id).first()
        assert last.ai["reused_from_run"] == first.public_id and last.ai["calls"] == 0
        assert last.ai["status"] == "ok" and last.ai["images_checked"] == 3
        from kk.auto_moderation import stats

        assert stats.summary(30)["ai"]["calls"] == 1  # the reused answer is not counted as a provider call


def test_ai_answer_is_never_reused_for_different_photos_or_after_an_unusable_answer(app, client, clean):
    calls = []
    _set_ai(calls=calls, overrides={0: {"_status": "unavailable", "error": "timeout"}})
    uid, token = _seller(app, client)
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["decision"] == "HOLD"
    assert _attach(client, token, c["public_id"], [_owned_url(app, uid, c["car_id"])], "damage").status_code == 201
    _run_job(app, "listing", c["car_id"])
    assert len(calls) == 2  # an outage is never carried over, new photos are never covered by an old answer


def test_media_changing_during_evaluation_discards_the_stale_verdict(app, client, clean, monkeypatch):
    """Image-processing race: a photo lands while the AI is still looking at the
    previous gallery. The verdict is for content that no longer exists."""
    from kk.auto_moderation import ai
    from kk.models import CarImage, db

    _live(monkeypatch, app)
    uid, _token = _seller(app, client)
    c = _car(app, uid)
    other = _owned_url(app, uid, c["car_id"])

    def photo_lands_during_ai(title, desc, urls):
        db.session.add(CarImage(car_id=c["car_id"], image_url=other, kind="damage", order=7, is_primary=False))
        db.session.commit()
        return _ai_ok_for(urls)

    ai.STUB_RESPONSE = photo_lands_during_ai
    out = _moderate(app, "listing", c["car_id"])
    assert out["outcome"] == "stale" and out["reenqueue"] is True
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert _runs(app, c["car_id"])[0]["status"] == "stale"
    # the next job judges the gallery as it is now (and may approve it)
    seen = []
    _set_ai(calls=seen)
    out = _moderate(app, "listing", c["car_id"])
    assert out["outcome"] == "published" and other in seen[0]["urls"]


def test_stale_approval_cannot_publish_changed_content(app, client, clean, monkeypatch):
    from kk.auto_moderation import engine

    _set_ai(calls=[])
    uid, token = _seller(app, client)
    c = _car(app, uid)
    _live(monkeypatch, app)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c["car_id"])
    assert _runs(app, c["car_id"])[0]["outcome"] == "pending_apply"
    monkeypatch.setattr(engine, "_apply", real_apply)
    rid = _runs(app, c["car_id"])[0]["id"]
    assert client.delete(
        f"/api/cars/{c['public_id']}/images/{c['image_ids'][2]}", headers=_auth(token)
    ).status_code == 200
    with app.app_context():
        out = real_apply(rid, "listing", c["car_id"])
    assert out["outcome"] == "stale" and out["reenqueue"] is True
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert not _runs(app, c["car_id"])[0]["applied"]


def test_shadow_mode_never_publishes_after_late_media(app, client, clean):
    _set_ai(calls=[])
    uid, token = _seller(app, client)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    assert _attach(client, token, c["public_id"], [_owned_url(app, uid, c["car_id"])], "damage").status_code == 201
    _run_job(app, "listing", c["car_id"])
    runs = _runs(app, c["car_id"])
    assert len(runs) == 2 and {r["outcome"] for r in runs} == {"shadow_would_approve"}
    assert all(r["mode"] == "shadow" and not r["applied"] for r in runs)
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_rules_first_ai_skip_still_applies_to_a_late_photo(app, client, clean):
    """An unproven seller is sent to a human by the rules; a late photo must not
    make the AI run (no extra cost) and the record says so."""
    calls = []
    _set_ai(calls=calls)
    uid, username = _user(app)
    token = _login(client, username)
    c = _car(app, uid)
    # an owned photo (the seller needs a second listing to own one)
    other = _car(app, uid, status="hidden", price=999, brand="kia", model="rio", title="Kia Rio 2020")
    url = f"{_CDN}/{other['car_id']}_0.jpg"
    _moderate(app, "listing", c["car_id"])
    assert _attach(client, token, c["public_id"], [url], "damage").status_code == 201
    _run_job(app, "listing", c["car_id"])
    assert calls == []
    from kk.models import ListingModerationRun

    with app.app_context():
        rows = ListingModerationRun.query.filter_by(car_id=c["car_id"]).order_by(ListingModerationRun.id).all()
        assert len(rows) == 2
        for r in rows:
            assert r.ai["status"] == "skipped" and r.ai["calls"] == 0 and r.ai["images_inspected"] is False
            assert "ai_images_not_inspected" in [x["code"] for x in r.reasons]
        assert rows[1].ai["images_expected"] == 4


# ---------------------------------------------------------------------------
# 4. Published listings keep using the revision workflow
# ---------------------------------------------------------------------------


def test_media_edit_of_a_published_listing_stays_in_its_working_copy(app, client, clean):
    _set_ai(calls=[])
    uid, token = _seller(app, client)
    live = _published_car(app, uid, price=16001, brand="kia", model="rio", title="Kia Rio 2019",
                          description="A different published listing with its own words.")
    from kk.models import CarImage

    other_url = _owned_url(app, uid, live["car_id"])
    before = _car_state(app, live["car_id"])
    clean.clear()
    assert _attach(client, token, live["public_id"], [other_url], "damage").status_code == 201
    with app.app_context():
        # the approved gallery is untouched; the new photo is in the hidden working copy
        assert CarImage.query.filter_by(car_id=live["car_id"], kind="damage").count() == 0
    assert _car_state(app, live["car_id"]) == before
    assert not any(j[0] == "listing" for j in _jobs(clean))  # a draft edit is never moderated
    assert _runs(app, live["car_id"]) == []


def test_late_photo_on_a_submitted_edit_reevaluates_the_revision_only(app, client, clean, monkeypatch):
    calls = []
    _set_ai(calls=calls)
    uid, token = _seller(app, client)
    live = _published_car(app, uid, price=16002, brand="kia", model="rio", title="Kia Rio 2019",
                          description="A different published listing with its own words.")
    rid, shadow_id, _p = _revision(app, live["car_id"], description="Updated: new tyres fitted, service done.")
    url = _owned_url(app, uid, live["car_id"])
    suffix = url.rsplit("/", 1)[1]
    _moderate(app, "revision", rid)
    first = len(calls)
    clean.clear()
    assert _attach(client, token, live["public_id"], [url], "damage").status_code == 201
    assert _jobs(clean) == [("revision", rid, _debounce())]
    _set_ai(calls=calls, overrides={len(calls): lambda urls: _photo_verdicts(urls, not_car=(suffix,))})
    _live(monkeypatch, app)
    out = _run_job(app, "revision", rid)
    assert len(calls) == first + 1
    assert out["decision"] == "NEEDS_REVIEW" and out["outcome"] == "queued_for_review"
    # the live listing never changed
    assert _car_state(app, live["car_id"])["description"].startswith("A different published")


# ---------------------------------------------------------------------------
# 5. Sweep: bounded content-token backstop
# ---------------------------------------------------------------------------


def _late_photo_without_trigger(app, car_id, url=None):
    """What the old media endpoints did: change the gallery, bump nothing."""
    from kk.models import CarImage, db

    with app.app_context():
        db.session.add(CarImage(car_id=car_id, image_url=url or f"{_CDN}/late_{uuid.uuid4().hex[:6]}.jpg",
                                kind="damage", order=8, is_primary=False))
        db.session.commit()


def _sweep(app, monkeypatch, tick=0):
    import kk.auto_moderation.sweep as sweep_mod

    enq = []
    monkeypatch.setattr(sweep_mod, "request_moderation", lambda t, i, **k: enq.append((t, i)) or True)
    monkeypatch.setattr(sweep_mod.time, "time", lambda: tick * sweep_mod.SWEEP_INTERVAL_SECONDS + 1)
    with app.app_context():
        return sweep_mod.sweep(), enq


def test_sweep_finds_a_gallery_changed_without_a_trigger(app, monkeypatch):
    _quiesce(app)
    _set_ai(calls=[])
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    res, enq = _sweep(app, monkeypatch)
    assert enq == [] and res["token_stale"] == 0 and res["token_checked"] == 1  # unchanged -> nothing
    _late_photo_without_trigger(app, c["car_id"])
    res, enq = _sweep(app, monkeypatch)
    assert enq == [("listing", c["car_id"])] and res["token_stale"] == 1


def test_sweep_finds_a_changed_submitted_edit(app, monkeypatch):
    _quiesce(app)
    _set_ai(calls=[])
    uid, _ = _trusted_seller(app)
    live = _published_car(app, uid, price=16003, brand="kia", model="rio", title="Kia Rio 2019",
                          description="A different published listing with its own words.")
    rid, shadow_id, _p = _revision(app, live["car_id"], description="Updated: new tyres fitted, service done.")
    _moderate(app, "revision", rid)
    res, enq = _sweep(app, monkeypatch)
    assert enq == []
    _late_photo_without_trigger(app, shadow_id)
    res, enq = _sweep(app, monkeypatch)
    assert enq == [("revision", rid)]


def test_sweep_never_enqueues_twice_for_the_same_content(app, monkeypatch):
    _quiesce(app)
    _set_ai(calls=[])
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    _late_photo_without_trigger(app, c["car_id"])
    res, enq = _sweep(app, monkeypatch)
    assert enq == [("listing", c["car_id"])]
    _moderate(app, "listing", c["car_id"])  # the job ran: a decision exists for the new token
    for tick in range(1, 6):
        res, enq = _sweep(app, monkeypatch, tick)
        assert enq == [] and res["token_stale"] == 0


def test_sweep_token_check_is_bounded_and_rotates(app, monkeypatch):
    import kk.auto_moderation.sweep as sweep_mod

    _quiesce(app)
    _set_ai(calls=[])
    monkeypatch.setattr(sweep_mod, "TOKEN_CHECK_LIMIT", 2)
    uid, _ = _trusted_seller(app)
    ids = []
    for n in range(5):
        c = _car(app, uid, price=17000 + n, vin=None)
        _moderate(app, "listing", c["car_id"])
        _late_photo_without_trigger(app, c["car_id"])
        ids.append(c["car_id"])
    seen = set()
    for tick in range(3):
        res, enq = _sweep(app, monkeypatch, tick)
        assert res["token_checked"] <= 2 and len(enq) <= 2  # a fixed budget, never the whole queue
        seen |= {i for _t, i in enq}
    assert seen == set(ids)  # ...yet every subject is reached within ceil(5 / 2) runs


def test_sweep_skips_a_subject_that_is_being_evaluated(app, monkeypatch):
    from kk.models import ListingModerationRun, db
    from kk.time_utils import utcnow

    _quiesce(app)
    _set_ai(calls=[])
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    _late_photo_without_trigger(app, c["car_id"])
    with app.app_context():
        r = ListingModerationRun.query.filter_by(car_id=c["car_id"]).one()
        r.status, r.claimed_at, r.decision, r.outcome = "evaluating", utcnow(), None, None
        db.session.commit()
    res, enq = _sweep(app, monkeypatch)
    assert enq == []  # the engine re-checks its own token when it finishes


def test_sweep_still_ignores_processing_media_and_never_decides(app, monkeypatch):
    _quiesce(app)
    uid, _ = _trusted_seller(app)
    _car(app, uid, media="processing")
    res, enq = _sweep(app, monkeypatch)
    assert enq == [] and res.get("candidates", 0) == 0
    assert _runs(app) == []


# ---------------------------------------------------------------------------
# 6. AI answer reuse: only for the identical question, never partial, always
#    re-judged by today's rules
# ---------------------------------------------------------------------------


def _evaluated_with_crop_pending(app, client, calls, **car_kw):
    """A listing evaluated once; returns (car, token, crop_it) where crop_it()
    changes ONLY the cover crop (a new content token the provider can't see)."""
    uid, token = _seller(app, client)
    c = _car(app, uid, **car_kw)
    _moderate(app, "listing", c["car_id"])
    assert len(calls) == 1
    state = {"focus": 0.1}

    def crop_it():
        state["focus"] += 0.1
        rows = [{"id": i, "order": n, "focus_y": state["focus"]} for n, i in enumerate(c["image_ids"])]
        assert client.put(
            f"/api/cars/{c['public_id']}/images/layout", json={"images": rows}, headers=_auth(token)
        ).status_code == 200
        return _run_job(app, "listing", c["car_id"])

    return c, token, crop_it


def test_reuse_happens_only_for_an_identical_question_control(app, client, clean):
    calls = []
    _set_ai(calls=calls)
    c, _t, crop_it = _evaluated_with_crop_pending(app, client, calls)
    crop_it()
    assert len(calls) == 1  # control: same question -> reused


@pytest.mark.parametrize("change", ["description", "title", "photo_url", "cover_photo"])
def test_changed_text_or_photos_are_never_covered_by_an_old_answer(app, client, clean, change):
    from kk.models import Car, CarImage, db

    calls = []
    _set_ai(calls=calls)
    c, token, crop_it = _evaluated_with_crop_pending(app, client, calls)
    uid = c["uid"]
    with app.app_context():
        if change == "description":
            Car.query.get(c["car_id"]).description = "Clean car, new tyres, serviced last month. No accidents."
        elif change == "title":
            Car.query.get(c["car_id"]).title = "Toyota Camry 2021 - one owner"
        elif change == "photo_url":  # same slot, a different file
            CarImage.query.get(c["image_ids"][2]).image_url = f"{_CDN}/{c['car_id']}_swapped.jpg"
        elif change == "cover_photo":  # a different photo is now the cover
            CarImage.query.get(c["image_ids"][0]).is_primary = False
            CarImage.query.get(c["image_ids"][1]).is_primary = True
            from kk.models import CarMediaItem

            for it in CarMediaItem.query.filter_by(car_id=c["car_id"]).all():  # the declared cover moves too
                it.is_cover = it.sort_order == 1
        db.session.commit()
    out = _run_job(app, "listing", c["car_id"])
    assert out["outcome"] != "done"
    assert len(calls) == 2  # asked the provider again; nothing was carried over
    from kk.models import ListingModerationRun

    with app.app_context():
        last = ListingModerationRun.query.filter_by(car_id=c["car_id"]).order_by(ListingModerationRun.id.desc()).first()
        assert "reused_from_run" not in last.ai


@pytest.mark.parametrize("change", ["model", "prompt", "effort", "version", "batching", "send_images"])
def test_changed_model_prompt_or_provider_settings_are_never_covered_by_an_old_answer(
    app, client, clean, monkeypatch, change
):
    from kk.auto_moderation import ai

    calls = []
    _set_ai(calls=calls)
    c, _t, crop_it = _evaluated_with_crop_pending(app, client, calls)
    if change == "model":
        monkeypatch.setenv("AUTO_MODERATION_AI_MODEL", "some-other-model")
    elif change == "prompt":
        monkeypatch.setattr(ai, "SYSTEM_PROMPT", ai.SYSTEM_PROMPT + " Be extra careful.")
    elif change == "effort":
        monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", "none")
    elif change == "version":
        monkeypatch.setattr(ai, "AI_RESULT_VERSION", ai.AI_RESULT_VERSION + 1)
    elif change == "batching":
        from kk.tests.test_auto_moderation_engine import _settings

        _settings(app, ai={"max_images": 2})
    elif change == "send_images":
        from kk.tests.test_auto_moderation_engine import _settings

        _settings(app, ai={"send_images": False})
    crop_it()
    assert len(calls) >= 2 if change != "send_images" else True
    if change == "send_images":
        assert len(calls) == 2  # asked again (text only); the old photo verdict is not reused


def _tamper_first_run_ai(app, car_id, fn):
    from kk.models import ListingModerationRun, db

    with app.app_context():
        r = ListingModerationRun.query.filter_by(car_id=car_id).order_by(ListingModerationRun.id).first()
        ai = dict(r.ai)
        fn(ai)
        r.ai = ai
        db.session.commit()


@pytest.mark.parametrize(
    "tamper",
    [
        lambda a: a.pop("input_hash"),  # recorded before reuse existed
        lambda a: a.update(images_checked=1),  # partial inspection
        lambda a: a.update(images_expected=2),
        lambda a: a.update(cover_checked=False, cover_expected=True),
        lambda a: a.update(status="uncertain"),
        lambda a: a.update(status="unavailable"),
        lambda a: a.update(status="disabled"),
        lambda a: a.update(input_hash="0" * 40),
    ],
    ids=["no_hash", "partial_checked", "wrong_expected", "cover_unchecked", "uncertain", "unavailable", "disabled", "other_hash"],
)
def test_incomplete_or_unusable_stored_answers_are_never_reused(app, client, clean, tamper):
    calls = []
    _set_ai(calls=calls)
    c, _t, crop_it = _evaluated_with_crop_pending(app, client, calls)
    _tamper_first_run_ai(app, c["car_id"], tamper)
    crop_it()
    assert len(calls) == 2


def test_reused_answer_is_rejudged_by_todays_settings(app, client, clean):
    """Only the provider's verdict is carried over; confidence bars, coverage and
    every rule are applied again with the CURRENT settings."""
    from kk.tests.test_auto_moderation_engine import _settings

    calls = []
    _set_ai(calls=calls, overrides={0: lambda urls: dict(_ai_ok_for(urls), confidence=0.8)})
    c, _t, crop_it = _evaluated_with_crop_pending(app, client, calls)
    _settings(app, ai={"min_confidence": 0.9})
    out = crop_it()
    assert len(calls) == 1  # reused ...
    assert out["decision"] == "NEEDS_REVIEW"  # ... and judged against the stricter bar
    assert "ai_low_confidence" in _runs(app, c["car_id"])[-1]["codes"]


def test_reused_answer_is_still_checked_against_the_gallery_at_apply(app, client, clean, monkeypatch):
    """Live: a reused answer cannot publish a gallery that differs from the
    inspected set (the apply-time gate compares photo count and cover)."""
    from kk.auto_moderation import engine

    calls = []
    _set_ai(calls=calls)
    c, _t, crop_it = _evaluated_with_crop_pending(app, client, calls)
    _live(monkeypatch, app)  # live mode records its own runs; first evaluate unpublished
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c["car_id"])  # live run #1: fresh AI call
    assert len(calls) == 2
    monkeypatch.setattr(engine, "_apply", real_apply)
    # reuse in live: crop only
    state = crop_it()
    assert len(calls) == 2 and state["outcome"] == "published"
    from kk.models import ListingModerationRun

    with app.app_context():
        last = ListingModerationRun.query.filter_by(car_id=c["car_id"]).order_by(ListingModerationRun.id.desc()).first()
        assert last.ai["reused_from_run"] and last.ai["images_checked"] == last.ai["images_expected"] == 3