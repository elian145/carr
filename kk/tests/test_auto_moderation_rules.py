"""Pure-function tests for the deterministic moderation rules, the AI result
normaliser, the settings validator and the decision precedence. No database."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.auto_moderation import ai, config, rules  # noqa: E402
from kk.auto_moderation.rules import Facts, HOLD, REVIEW  # noqa: E402

YEAR = 2026
S = config.DEFAULTS


def _fields(**kw):
    base = dict(
        title="Toyota Camry 2021",
        brand="toyota",
        model="camry",
        year=2021,
        mileage=45000,
        price=15000.0,
        currency="USD",
        location="Erbil",
        condition="used",
        engine_type="gasoline",
        transmission="automatic",
        drive_type="fwd",
        body_type="sedan",
        vin=None,
        description="Clean car, regularly serviced, no accidents.",
    )
    base.update(kw)
    return base


def _media(n=3, **kw):
    images = [
        {
            "url": f"https://cdn.example.com/p{i}.jpg",
            "kind": "listing",
            "is_primary": i == 0,
            "source_media_id": f"m{i}",
            "width": 1600,
            "height": 1200,
        }
        for i in range(n)
    ]
    items = [
        {"client_media_id": f"m{i}", "kind": "image", "status": "attached", "is_cover": i == 0}
        for i in range(n)
    ]
    base = dict(media_status="ready", in_flight=0, failed=0, items=items, images=images)
    base.update(kw)
    return base


def _seller(**kw):
    base = dict(
        exists=True,
        active=True,
        phone_verified=True,
        dealer_approved=False,
        prior_approved=2,
        open_reports=0,
        admin_rejections=0,
        hidden_listings=0,
        manual_only=False,
    )
    base.update(kw)
    return base


def _facts(fields=None, media=None, seller=None, dup=None, subject="listing", revision=None):
    return Facts(
        subject_type=subject,
        fields=fields or _fields(),
        media=media or _media(),
        seller=seller or _seller(),
        duplicates=dup or {},
        revision=revision,
    )


def _codes(signals, level=None):
    return {s.code for s in signals if level is None or s.level == level}


def test_clean_listing_has_no_blocking_signal():
    sigs = rules.run_rules(_facts(), S, YEAR)
    assert [s for s in sigs if s.level in (HOLD, REVIEW)] == []
    assert rules.decide(sigs) == "AUTO_APPROVE"


@pytest.mark.parametrize("field", ["brand", "model", "location", "transmission", "body_type"])
def test_missing_or_placeholder_required_field_needs_review(field):
    for bad in ("", "unknown", "N/A"):
        sigs = rules.run_rules(_facts(fields=_fields(**{field: bad})), S, YEAR)
        assert "missing_field" in _codes(sigs, REVIEW)


@pytest.mark.parametrize(
    "kw,code",
    [
        ({"year": 1900}, "year_out_of_range"),
        ({"year": YEAR + 5}, "year_out_of_range"),
        ({"mileage": 5_000_000}, "mileage_out_of_range"),
        ({"mileage": -1}, "mileage_out_of_range"),
        ({"price": 0}, "price_invalid"),
        ({"price": 20.0}, "price_out_of_range"),
        ({"price": 9_000_000.0}, "price_out_of_range"),
        ({"currency": "XYZ"}, "unknown_currency"),
        ({"vin": "NOT-A-VIN"}, "vin_invalid"),
        ({"condition": "new", "mileage": 30000}, "new_with_mileage"),
        ({"condition": "new", "year": 2015, "mileage": 0}, "new_but_old_year"),
        ({"mileage": 0}, "used_zero_mileage"),
    ],
)
def test_value_sanity_rules(kw, code):
    sigs = rules.run_rules(_facts(fields=_fields(**kw)), S, YEAR)
    assert code in _codes(sigs, REVIEW)
    assert rules.decide(sigs) == "NEEDS_REVIEW"


def test_valid_vin_and_iqd_pricing_pass():
    f = _fields(vin="1HGCM82633A004352", currency="IQD", price=21_000_000.0)
    assert [s for s in rules.run_rules(_facts(fields=f), S, YEAR) if s.level in (HOLD, REVIEW)] == []


@pytest.mark.parametrize(
    "text,code",
    [
        ("Guaranteed profit if you contact me now", "scam_language"),
        ("send gift card first", "scam_language"),
        ("ربح مضمون للجميع", "scam_language"),
        ("also selling a rifle and ammunition", "prohibited_content"),
        ("brand new iPhone included", "non_car_content"),
        ("aaaaaaaaaaaaaaaaaaaa great car", "repeated_characters"),
        ("call me 07501234567 anytime", "contact_in_description"),
        ("see https://example.com/car", "contact_in_description"),
        ("mail me at seller@example.com", "contact_in_description"),
        ("buy " * 40, "repetitive_text"),
    ],
)
def test_text_rules_route_to_review_never_reject(text, code):
    sigs = rules.run_rules(_facts(fields=_fields(description=text)), S, YEAR)
    assert code in _codes(sigs, REVIEW)
    assert rules.decide(sigs) in ("NEEDS_REVIEW",)  # never a reject decision


def test_gun_metal_color_and_normal_phrases_are_not_flagged():
    sigs = rules.run_rules(
        _facts(fields=_fields(description="Gun metal grey, one owner, full service history.")),
        S,
        YEAR,
    )
    assert rules.decide(sigs) == "AUTO_APPROVE"


def test_contact_in_description_check_is_configurable():
    s = dict(S, flag_contact_in_description=False)
    sigs = rules.run_rules(_facts(fields=_fields(description="call 07501234567")), s, YEAR)
    assert "contact_in_description" not in _codes(sigs)


def test_media_in_flight_is_hold_not_review():
    sigs = rules.run_rules(_facts(media=_media(media_status="processing", in_flight=2)), S, YEAR)
    assert "media_processing" in _codes(sigs, HOLD)
    assert rules.decide(sigs) == "HOLD"


def test_media_failed_is_hold():
    sigs = rules.run_rules(_facts(media=_media(media_status="failed", failed=1)), S, YEAR)
    assert "media_failed" in _codes(sigs, HOLD)
    assert rules.decide(sigs) == "HOLD"


def test_no_photos_and_min_photos_policy():
    sigs = rules.run_rules(_facts(media=_media(0)), S, YEAR)
    assert "too_few_photos" in _codes(sigs, REVIEW)
    s0 = dict(S, min_photos=0)
    assert "too_few_photos" not in _codes(rules.run_rules(_facts(media=_media(0)), s0, YEAR))


def test_cover_rules():
    m = _media()
    for img in m["images"]:
        img["is_primary"] = False
    assert "cover_invalid" in _codes(rules.run_rules(_facts(media=m), S, YEAR), REVIEW)

    m = _media()
    m["images"][1]["is_primary"] = True  # two primaries
    assert "cover_invalid" in _codes(rules.run_rules(_facts(media=m), S, YEAR), REVIEW)

    # declared cover (m0) is not the stored cover (m1 is)
    m = _media()
    m["images"][0]["is_primary"] = False
    m["images"][1]["is_primary"] = True
    assert "cover_mismatch" in _codes(rules.run_rules(_facts(media=m), S, YEAR), REVIEW)


def test_attached_item_without_photo_is_missing_media():
    m = _media()
    m["images"].pop(2)
    assert "media_missing" in _codes(rules.run_rules(_facts(media=m), S, YEAR), REVIEW)


def test_low_resolution_photo_flagged():
    m = _media()
    m["images"][1]["width"], m["images"][1]["height"] = 200, 150
    assert "low_resolution" in _codes(rules.run_rules(_facts(media=m), S, YEAR), REVIEW)


def test_damage_photos_do_not_count_as_listing_photos():
    m = _media(1)
    m["images"].append(
        {"url": "https://cdn.example.com/d.jpg", "kind": "damage", "is_primary": False,
         "source_media_id": None, "width": 800, "height": 600}
    )
    s = dict(S, min_photos=2)
    assert "too_few_photos" in _codes(rules.run_rules(_facts(media=m), s, YEAR), REVIEW)


@pytest.mark.parametrize(
    "dup,code",
    [
        ({"own_similar": 1}, "duplicate_listing"),
        ({"own_same_description": 1}, "repeated_description"),
        ({"vin_own": 1}, "vin_reused_own"),
        ({"vin_other_seller": 1}, "vin_other_seller"),
        ({"recent_24h": 99}, "high_posting_rate"),
    ],
)
def test_duplicate_and_abuse_signals(dup, code):
    assert code in _codes(rules.run_rules(_facts(dup=dup), S, YEAR), REVIEW)


@pytest.mark.parametrize(
    "seller,code",
    [
        (_seller(exists=False), "seller_missing"),
        (_seller(active=False), "seller_inactive"),
        (_seller(phone_verified=False), "seller_not_verified"),
        (_seller(open_reports=1), "seller_open_reports"),
        (_seller(admin_rejections=1), "seller_abuse_history"),
        (_seller(hidden_listings=2), "seller_abuse_history"),
        (_seller(prior_approved=0), "seller_unproven"),
        (_seller(manual_only=True), "pinned_manual_review"),
    ],
)
def test_seller_signals(seller, code):
    sigs = rules.run_rules(_facts(seller=seller), S, YEAR)
    assert code in _codes(sigs, REVIEW)
    assert rules.decide(sigs) == "NEEDS_REVIEW"


def test_approved_dealer_counts_as_trusted_without_history():
    seller = _seller(prior_approved=0, dealer_approved=True)
    assert "seller_unproven" not in _codes(rules.run_rules(_facts(seller=seller), S, YEAR))
    s = dict(S, dealers_count_as_trusted=False)
    assert "seller_unproven" in _codes(rules.run_rules(_facts(seller=seller), s, YEAR))


def test_routine_vs_suspicious_flags():
    sigs = rules.run_rules(_facts(seller=_seller(prior_approved=0)), S, YEAR)
    unproven = next(s for s in sigs if s.code == "seller_unproven")
    assert unproven.suspicious is False
    sigs = rules.run_rules(_facts(fields=_fields(description="western union only")), S, YEAR)
    assert next(s for s in sigs if s.code == "scam_language").suspicious is True


def test_payment_required_can_never_be_assumed_paid():
    s = dict(S, listing_payment_required=True)
    sigs = rules.run_rules(_facts(), s, YEAR)
    assert "payment_unverifiable" in _codes(sigs, REVIEW)
    # edits of an already-published listing do not re-check payment
    sigs = rules.run_rules(
        _facts(subject="revision", revision={"changed_fields": ["description"], "old_price": 1, "new_price": 1}),
        s,
        YEAR,
    )
    assert "payment_unverifiable" not in _codes(sigs)


def test_revision_rules():
    rev = {"changed_fields": ["brand", "price"], "old_price": 10000.0, "new_price": 2000.0, "new_media": False}
    sigs = rules.run_rules(_facts(subject="revision", revision=rev), S, YEAR)
    assert {"identity_changed", "large_price_change"} <= _codes(sigs, REVIEW)
    rev = {"changed_fields": [], "old_price": 1.0, "new_price": 1.0, "new_media": False}
    assert "no_effective_changes" in _codes(
        rules.run_rules(_facts(subject="revision", revision=rev), S, YEAR), REVIEW
    )
    rev = {"changed_fields": ["description"], "old_price": 10000.0, "new_price": 10500.0, "new_media": False}
    sigs = rules.run_rules(_facts(subject="revision", revision=rev), S, YEAR)
    assert [s for s in sigs if s.level in (HOLD, REVIEW)] == []


# ---- decision precedence ---------------------------------------------------


def test_decision_precedence_hold_over_review_over_approve():
    a = rules.Signal("x", REVIEW, "text")
    h = rules.Signal("y", HOLD, "media")
    i = rules.Signal("z", "info", "text")
    assert rules.decide([]) == "AUTO_APPROVE"
    assert rules.decide([i]) == "AUTO_APPROVE"
    assert rules.decide([a]) == "NEEDS_REVIEW"
    assert rules.decide([a, h]) == "HOLD"


def test_checks_map_statuses():
    sigs = [rules.Signal("a", REVIEW, "text"), rules.Signal("b", HOLD, "media")]
    cm = rules.checks_map(sigs, ("text", "media", "values"))
    assert cm["text"] == "fail" and cm["media"] == "hold" and cm["values"] == "pass"
    assert cm["ai"] == "skipped"


# ---- AI signals + response normalisation -----------------------------------


def test_ai_signals_never_turn_failure_into_approval():
    assert rules.decide(rules.ai_signals({"status": "unavailable", "error": "timeout"}, S)) == "HOLD"
    assert rules.decide(rules.ai_signals({"status": "uncertain"}, S)) == "NEEDS_REVIEW"
    assert rules.decide(rules.ai_signals({"status": "flagged", "text_flags": ["scam"], "image_flags": []}, S)) == "NEEDS_REVIEW"
    assert rules.decide(rules.ai_signals({"status": "disabled"}, S)) == "NEEDS_REVIEW"  # AI required by default
    assert rules.decide(rules.ai_signals({"status": "disabled"}, dict(S, require_ai_for_auto_approve=False))) == "AUTO_APPROVE"
    assert rules.decide(rules.ai_signals({"status": "ok", "confidence": 0.2}, S)) == "NEEDS_REVIEW"
    assert rules.decide(rules.ai_signals({"status": "ok", "confidence": 0.95}, S)) == "AUTO_APPROVE"
    assert rules.decide(rules.ai_signals({"status": "not_needed"}, S)) == "AUTO_APPROVE"


def _good(n=2):
    return {
        "text": {"ok": True, "flags": []},
        "images": [{"index": i, "is_car_photo": True, "flags": []} for i in range(n)],
        "confidence": 0.9,
        "notes": "n",
    }


def test_normalize_response_ok_and_flagged():
    assert ai.normalize_response(_good(), images_sent=2)["status"] == "ok"
    bad = _good()
    bad["images"][1]["is_car_photo"] = False
    r = ai.normalize_response(bad, images_sent=2)
    assert r["status"] == "flagged" and "not_a_car" in r["image_flags"]
    bad = _good()
    bad["text"] = {"ok": False, "flags": ["scam", "made_up_flag"]}
    r = ai.normalize_response(bad, images_sent=2)
    assert r["status"] == "flagged" and r["text_flags"] == ["scam"]


@pytest.mark.parametrize(
    "raw",
    [None, "text", {}, {"text": {"ok": "yes"}}, {"text": {"ok": True}, "images": "x"},
     {"text": {"ok": True}, "images": [{"index": "0"}]}],
)
def test_normalize_response_garbage_is_uncertain_not_ok(raw):
    assert ai.normalize_response(raw, images_sent=0)["status"] == "uncertain"


def test_normalize_response_missing_image_verdicts_is_uncertain():
    r = ai.normalize_response(_good(1), images_sent=3)
    assert r["status"] == "uncertain"


def test_redaction_removes_contact_details_before_provider():
    t = rules.redact_for_provider("Call +964 750 123 4567 or a@b.com or https://x.com/car now")
    assert "750" not in t and "a@b.com" not in t and "x.com" not in t
    assert "[phone]" in t and "[email]" in t and "[link]" in t


def test_provider_disabled_without_configuration(monkeypatch):
    monkeypatch.delenv("AUTO_MODERATION_AI_PROVIDER", raising=False)
    r = ai.moderate(title="t", description="d", image_urls=[], settings=S)
    assert r["status"] == "disabled"
    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "openai")
    for k in ("AUTO_MODERATION_OPENAI_API_KEY", "OPENAI_API_KEY"):
        monkeypatch.delenv(k, raising=False)
    assert ai.moderate(title="t", description="d", image_urls=[], settings=S)["status"] == "disabled"


def test_provider_failures_map_to_unavailable(monkeypatch):
    import requests

    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "openai")
    monkeypatch.setenv("AUTO_MODERATION_OPENAI_API_KEY", "sk-test-secret")

    class Resp:
        def __init__(self, code, body=None):
            self.status_code = code
            self._b = body

        def json(self):
            return self._b

    def boom(*a, **k):
        raise requests.Timeout("slow")

    monkeypatch.setattr(requests, "post", boom)
    r = ai.moderate(title="t", description="d", image_urls=[], settings=S)
    assert r["status"] == "unavailable" and r["error"] == "timeout"

    monkeypatch.setattr(requests, "post", lambda *a, **k: Resp(503))
    r = ai.moderate(title="t", description="d", image_urls=[], settings=S)
    assert r["status"] == "unavailable" and r["error"] == "http_503"

    monkeypatch.setattr(
        requests, "post",
        lambda *a, **k: Resp(200, {"choices": [{"message": {"content": "not json"}}]}),
    )
    r = ai.moderate(title="t", description="d", image_urls=[], settings=S)
    assert r["status"] == "uncertain"
    assert "sk-test-secret" not in str(r)

    good = {"text": {"ok": True, "flags": []}, "images": [], "confidence": 0.9}
    import json as _json

    monkeypatch.setattr(
        requests, "post",
        lambda *a, **k: Resp(200, {"choices": [{"message": {"content": _json.dumps(good)}}]}),
    )
    assert ai.moderate(title="t", description="d", image_urls=[], settings=S)["status"] == "ok"


def test_provider_payload_has_no_contact_data_and_caps_images(monkeypatch):
    import json as _json
    import requests

    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "openai")
    monkeypatch.setenv("AUTO_MODERATION_OPENAI_API_KEY", "sk-test")
    seen = {}

    class Resp:
        status_code = 200

        def json(self):
            ok = {"text": {"ok": True, "flags": []},
                  "images": [{"index": i, "is_car_photo": True, "flags": []} for i in range(2)],
                  "confidence": 0.9}
            return {"choices": [{"message": {"content": _json.dumps(ok)}}]}

    def fake_post(url, headers=None, json=None, timeout=None):
        seen["body"] = json
        seen["timeout"] = timeout
        return Resp()

    monkeypatch.setattr(requests, "post", fake_post)
    settings = dict(S, ai=dict(S["ai"], max_images=2, timeout_seconds=7))
    urls = [f"https://cdn.example.com/{i}.jpg" for i in range(6)] + ["http://insecure/x.jpg"]
    r = ai.moderate(title="Camry", description="call 07501234567 now", image_urls=urls, settings=settings)
    assert r["status"] == "ok"
    payload = _json.dumps(seen["body"])
    assert "07501234567" not in payload
    assert payload.count('"type": "image_url"') == 2  # capped to max_images, https only
    assert "insecure" not in payload
    assert seen["timeout"] == 7


# ---- settings validation ---------------------------------------------------


def test_validate_patch_rejects_unknown_and_out_of_range():
    for bad in (
        {"nope": 1},
        {"mode": "auto"},
        {"min_photos": 99},
        {"ai": {"timeout_seconds": 1}},
        {"ai": {"api_key": "x"}},
        {"alerts": {"channels": ["sms"]}},
        {"alerts": {"email_recipients": ["not-an-email"]}},
        {"gate": {"max_unsafe_approve_rate": 3}},
        {"currency_price_bounds": {"USD": [10, 5]}},
        {"auto_approve_revisions": "yes"},
    ):
        with pytest.raises(ValueError):
            config.validate_patch(bad)


def test_validate_patch_accepts_valid_and_never_accepts_secrets():
    out = config.validate_patch(
        {
            "mode": "shadow",
            "min_photos": 3,
            "alerts": {"enabled": True, "channels": ["telegram", "email", "email"],
                       "email_recipients": ["Ops@Example.com"]},
            "currency_price_bounds": {"usd": [1000, 500000]},
        }
    )
    assert out["alerts"]["channels"] == ["email", "telegram"]
    assert out["alerts"]["email_recipients"] == ["ops@example.com"]
    assert out["currency_price_bounds"] == {"USD": [1000.0, 500000.0]}
    with pytest.raises(ValueError):
        config.validate_patch({"alerts": {"telegram_bot_token": "x"}})


def test_effective_mode_rules(monkeypatch):
    for k in ("AUTO_MODERATION_DISABLED", "AUTO_MODERATION_KILL_SWITCH", "AUTO_MODERATION_ALLOW_LIVE"):
        monkeypatch.delenv(k, raising=False)
    live = dict(S, mode="live")
    assert config.effective_mode(dict(S)) == "shadow"          # default
    assert config.effective_mode(live) == "shadow"             # env does not allow live
    monkeypatch.setenv("AUTO_MODERATION_ALLOW_LIVE", "1")
    assert config.effective_mode(live) == "live"
    assert config.effective_mode(dict(live, kill_switch=True)) == "shadow"
    monkeypatch.setenv("AUTO_MODERATION_KILL_SWITCH", "1")
    assert config.effective_mode(live) == "shadow"
    monkeypatch.delenv("AUTO_MODERATION_KILL_SWITCH")
    assert config.effective_mode(dict(S, mode="off")) == "off"
    monkeypatch.setenv("AUTO_MODERATION_DISABLED", "1")
    assert config.effective_mode(live) == "off"
    assert config.DEFAULTS["mode"] == "shadow"


def test_public_settings_never_contain_secrets(monkeypatch):
    monkeypatch.setenv("AUTO_MODERATION_TELEGRAM_BOT_TOKEN", "123:SECRET")
    monkeypatch.setenv("AUTO_MODERATION_TELEGRAM_CHAT_ID", "-100999")
    monkeypatch.setenv("AUTO_MODERATION_OPENAI_API_KEY", "sk-live-SECRET")
    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "openai")
    import json as _json

    blob = _json.dumps(config.public_settings(dict(S)))
    assert "SECRET" not in blob and "-100999" not in blob
    assert '"telegram_configured": true' in blob and '"ai_configured": true' in blob
