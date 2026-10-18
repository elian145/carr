"""OpenAI adapter of automated listing moderation: request shape and fail-closed
handling, including reasoning models such as ``gpt-6-luna``.

Pins the contract:

* ``AUTO_MODERATION_AI_REASONING_EFFORT`` unset/blank -> ``reasoning_effort`` is
  NOT in the request (models that reject it keep working);
* set -> sent verbatim (lower-cased); an unknown value makes NO request;
* the rest of the request (endpoint, ``json_object``, 500 tokens, ``image_url``
  parts, batching) is unchanged;
* empty / truncated / non-JSON / incomplete output is ``uncertain``
  (NEEDS_REVIEW), HTTP errors and timeouts are ``unavailable`` (HOLD) -- no
  failure mode can produce an approval, and a partial inspection is never ``ok``.

No test reaches the network: ``requests.post`` is always replaced, and the API
key is a dummy.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest
import requests

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.auto_moderation import ai, config, rules  # noqa: E402

_DUMMY_KEY = "sk-DUMMY-not-a-real-key"
_URL = "https://api.openai.com/v1/chat/completions"
_PHOTOS = [f"https://cdn.example.com/car_photos/{i}.jpg" for i in range(4)]


class FakeResponse:
    def __init__(self, status=200, body=None, not_json=False):
        self.status_code = status
        self._body = body
        self._not_json = not_json

    def json(self):
        if self._not_json:
            raise ValueError("response is not JSON")
        return self._body


def chat(content, finish="stop", **message_extra):
    """A Chat Completions success body."""
    return {
        "choices": [
            {"index": 0, "finish_reason": finish, "message": {"role": "assistant", "content": content, **message_extra}}
        ]
    }


def verdict(n_images, *, text_ok=True, flags=None, is_car=True, confidence=0.95):
    return json.dumps(
        {
            "text": {"ok": text_ok, "flags": flags or []},
            "images": [{"index": i, "is_car_photo": is_car, "flags": []} for i in range(n_images)],
            "confidence": confidence,
            "notes": "ok",
        }
    )


@pytest.fixture(autouse=True)
def openai_env(monkeypatch):
    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "openai")
    monkeypatch.setenv("AUTO_MODERATION_OPENAI_API_KEY", _DUMMY_KEY)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("AUTO_MODERATION_AI_MODEL", raising=False)
    monkeypatch.delenv("AUTO_MODERATION_AI_REASONING_EFFORT", raising=False)
    ai.STUB_RESPONSE = None


@pytest.fixture
def calls(monkeypatch):
    """Replace requests.post; every call is recorded, nothing leaves the process."""
    c = _Calls()

    def fake_post(url, headers=None, json=None, timeout=None, **kw):  # noqa: A002
        c.sent.append({"url": url, "headers": headers, "json": json, "timeout": timeout})
        result = c._respond(json)
        if isinstance(result, BaseException):
            raise result
        return result

    monkeypatch.setattr(ai.requests, "post", fake_post)
    return c


class _Calls:
    def __init__(self):
        self.sent: list[dict] = []
        self._respond = lambda body: FakeResponse(200, chat(verdict(_n_images(body))))

    def respond(self, value):
        """Fixed response (or exception) for every request."""
        self._respond = lambda body: value

    def respond_with(self, fn):
        self._respond = fn


def _n_images(body):
    parts = body["messages"][1]["content"]
    return sum(1 for p in parts if p["type"] == "image_url")


def _moderate(photos=_PHOTOS, **settings_patch):
    s = json.loads(json.dumps(config.DEFAULTS))
    s["ai"].update(settings_patch)
    return ai.moderate(
        title="Toyota Camry 2021", description="Clean car, one owner.", image_urls=list(photos), settings=s,
        cover_needed=True,
    )


def _signal_codes(result):
    s = json.loads(json.dumps(config.DEFAULTS))
    s["ai_required_effective"] = True
    return [sig.code for sig in rules.ai_signals(result, s)]


def _fails_closed(result):
    """Not an approval: not ``ok``, and the rules turn it into at least one
    signal (hold or review) that blocks AUTO_APPROVE."""
    assert result["status"] in ("uncertain", "unavailable"), result
    assert _signal_codes(result), "a failed inspection must add a blocking signal"


# ---------------------------------------------------------------------------
# reasoning_effort: absent / present / correct value
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("model", [None, "gpt-4o-mini", "gpt-4.1-mini", "gpt-6-luna"])
def test_reasoning_effort_absent_when_env_unset(monkeypatch, calls, model):
    if model:
        monkeypatch.setenv("AUTO_MODERATION_AI_MODEL", model)
    r = _moderate()
    assert r["status"] == "ok"
    body = calls.sent[0]["json"]
    assert "reasoning_effort" not in body
    assert body["model"] == (model or "gpt-4o-mini")  # historical default preserved


@pytest.mark.parametrize("blank", ["", "   "])
def test_blank_env_is_treated_as_unset(monkeypatch, calls, blank):
    monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", blank)
    assert _moderate()["status"] == "ok"
    assert "reasoning_effort" not in calls.sent[0]["json"]


def test_gpt_6_luna_request_with_effort_none(monkeypatch, calls):
    monkeypatch.setenv("AUTO_MODERATION_AI_MODEL", "gpt-6-luna")
    monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", "none")
    r = _moderate()
    assert r["status"] == "ok" and r["images_checked"] == 4 and r["cover_checked"] is True
    req = calls.sent[0]
    assert req["url"] == _URL
    assert req["headers"]["Authorization"] == f"Bearer {_DUMMY_KEY}"
    body = req["json"]
    assert body["model"] == "gpt-6-luna"
    assert body["reasoning_effort"] == "none"  # the STRING "none", not null/omitted
    assert body["response_format"] == {"type": "json_object"}
    assert body["max_completion_tokens"] == 500
    assert "max_tokens" not in body and "temperature" not in body
    assert [m["role"] for m in body["messages"]] == ["system", "user"]
    parts = body["messages"][1]["content"]
    assert parts[0]["type"] == "text"
    assert [p["image_url"]["url"] for p in parts[1:]] == _PHOTOS
    assert all(p["type"] == "image_url" for p in parts[1:])
    assert set(body) == {"model", "messages", "response_format", "max_completion_tokens", "reasoning_effort"}


@pytest.mark.parametrize(
    "configured, sent",
    [("none", "none"), ("NONE", "none"), ("  None ", "none"), ("low", "low"), ("Medium", "medium"),
     ("high", "high"), ("minimal", "minimal"), ("xhigh", "xhigh"), ("max", "max")],
)
def test_reasoning_effort_value_is_sent_normalised(monkeypatch, calls, configured, sent):
    monkeypatch.setenv("AUTO_MODERATION_AI_MODEL", "gpt-6-luna")
    monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", configured)
    _moderate()
    assert calls.sent[0]["json"]["reasoning_effort"] == sent


@pytest.mark.parametrize("bad", ["off", "nope", "0", "none;drop", "very high"])
def test_unknown_reasoning_effort_makes_no_request_and_fails_closed(monkeypatch, calls, bad):
    monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", bad)
    r = _moderate()
    assert calls.sent == []  # no request, so no spend
    assert r["status"] == "unavailable" and r["error"] == "invalid_reasoning_effort"
    assert _signal_codes(r) == ["ai_unavailable"]


def test_reasoning_effort_is_sent_on_every_batch_and_batching_is_unchanged(monkeypatch, calls):
    monkeypatch.setenv("AUTO_MODERATION_AI_MODEL", "gpt-6-luna")
    monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", "none")
    photos = [f"https://cdn.example.com/car_photos/{i}.jpg" for i in range(6)]
    r = _moderate(photos)
    assert r["status"] == "ok" and r["images_checked"] == 6 and r["images_expected"] == 6
    assert len(calls.sent) == 2
    assert [_n_images(c["json"]) for c in calls.sent] == [4, 2]
    assert all(c["json"]["reasoning_effort"] == "none" for c in calls.sent)
    # listing text is judged by the first request only
    assert "<listing_text>" in calls.sent[0]["json"]["messages"][1]["content"][0]["text"]
    assert "<listing_text>" not in calls.sent[1]["json"]["messages"][1]["content"][0]["text"]


def test_too_many_images_makes_no_request(monkeypatch, calls):
    monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", "none")
    r = _moderate([f"https://cdn.example.com/{i}.jpg" for i in range(13)])
    assert calls.sent == []
    assert r["status"] == "uncertain" and r["error"] == "too_many_images"
    assert _signal_codes(r) == ["ai_image_coverage_incomplete"]


# ---------------------------------------------------------------------------
# Valid output still works (the patch must not weaken the happy path)
# ---------------------------------------------------------------------------


def test_valid_json_is_ok_and_leaves_no_signal(monkeypatch, calls):
    monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", "none")
    r = _moderate()
    assert r["status"] == "ok" and r["error"] is None
    assert _signal_codes(r) == []


def test_fenced_json_is_still_accepted(monkeypatch, calls):
    calls.respond(FakeResponse(200, chat("```json\n" + verdict(4) + "\n```")))
    assert _moderate()["status"] == "ok"


def test_flagged_content_goes_to_review(monkeypatch, calls):
    calls.respond(FakeResponse(200, chat(verdict(4, text_ok=False, flags=["scam"]))))
    r = _moderate()
    assert r["status"] == "flagged" and "scam" in r["text_flags"]
    assert _signal_codes(r) == ["ai_flagged"]


# ---------------------------------------------------------------------------
# Empty, truncated, invalid output -> uncertain (NEEDS_REVIEW), never ok
# ---------------------------------------------------------------------------


def test_reasoning_budget_exhausted_empty_content_is_uncertain(monkeypatch, calls):
    """gpt-6-luna at its default (medium) effort: reasoning uses the 500-token
    cap, finish_reason is "length" and there is no visible output."""
    monkeypatch.setenv("AUTO_MODERATION_AI_MODEL", "gpt-6-luna")
    calls.respond(FakeResponse(200, chat("", "length")))
    r = _moderate()
    assert r["status"] == "uncertain" and r["error"] == "truncated_response"
    assert r["images_checked"] == 0
    _fails_closed(r)


def test_truncated_json_with_length_finish_is_uncertain(calls):
    calls.respond(FakeResponse(200, chat(verdict(4)[:80], "length")))
    r = _moderate()
    assert r["status"] == "uncertain" and r["error"] == "truncated_response"
    _fails_closed(r)


def test_complete_json_with_length_finish_is_not_trusted(calls):
    # The budget ran out exactly at the end: do not approve on a cut-off answer.
    calls.respond(FakeResponse(200, chat(verdict(4), "length")))
    r = _moderate()
    assert r["status"] == "uncertain" and r["error"] == "truncated_response"
    _fails_closed(r)


@pytest.mark.parametrize(
    "content",
    [
        "",  # empty with a normal stop
        None,  # refusals / filtered output have no content
        "Looks fine to me!",  # prose
        verdict(4)[:80],  # cut-off JSON that still said "stop"
        "[1, 2, 3]",  # JSON, but not an object
        "null",
        json.dumps({"images": []}),  # missing text verdict
        json.dumps({"text": {"ok": "yes"}, "images": []}),  # text.ok not a boolean
        json.dumps({"text": {"ok": True, "flags": []}, "images": "none"}),  # images not a list
        json.dumps({"text": {"ok": True, "flags": []}, "images": [{"index": "0"}]}),  # bad index
    ],
)
def test_invalid_or_empty_content_is_uncertain(calls, content):
    calls.respond(FakeResponse(200, chat(content)))
    r = _moderate()
    assert r["status"] == "uncertain" and r["error"] == "invalid_response"
    assert r["images_checked"] == 0
    _fails_closed(r)


def test_refusal_message_is_uncertain(calls):
    calls.respond(FakeResponse(200, chat(None, "stop", refusal="I can't help with that.")))
    r = _moderate()
    assert r["status"] == "uncertain"
    _fails_closed(r)


@pytest.mark.parametrize("body", [{}, {"choices": []}, {"choices": ["oops"]}, {"choices": [{}]}, {"error": {}}])
def test_malformed_response_body_is_uncertain(calls, body):
    calls.respond(FakeResponse(200, body))
    r = _moderate()
    assert r["status"] == "uncertain" and r["error"] == "invalid_response"
    _fails_closed(r)


def test_non_json_http_body_is_uncertain(calls):
    calls.respond(FakeResponse(200, not_json=True))
    r = _moderate()
    assert r["status"] == "uncertain"
    _fails_closed(r)


def test_missing_image_verdicts_never_count_as_checked(calls):
    calls.respond(FakeResponse(200, chat(verdict(3))))  # 4 photos sent, 3 judged
    r = _moderate()
    assert r["status"] == "uncertain" and r["error"] == "incomplete_image_verdicts"
    assert r["images_checked"] == 0
    _fails_closed(r)


def test_extra_image_verdicts_are_rejected_too(calls):
    calls.respond(FakeResponse(200, chat(verdict(5))))
    r = _moderate()
    assert r["status"] == "uncertain"
    _fails_closed(r)


def test_partial_coverage_is_never_a_clean_result():
    """Defence in depth in the rules: an ``ok`` that inspected fewer photos
    than expected (or not the cover) still blocks approval."""
    base = {"status": "ok", "images_expected": 4, "images_checked": 3, "cover_expected": True, "cover_checked": True,
            "confidence": 0.95}
    assert _signal_codes(base) == ["ai_image_coverage_incomplete"]
    assert _signal_codes({**base, "images_checked": 4, "cover_checked": False}) == ["ai_cover_not_checked"]
    assert _signal_codes({**base, "images_checked": 4}) == []


# ---------------------------------------------------------------------------
# HTTP errors and timeouts -> unavailable (HOLD)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("code", [400, 401, 403, 404, 408, 409, 422, 429, 500, 502, 503, 504])
def test_http_errors_are_unavailable_hold(monkeypatch, calls, code):
    monkeypatch.setenv("AUTO_MODERATION_AI_MODEL", "gpt-6-luna")
    monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", "none")
    calls.respond(FakeResponse(code, {"error": {"message": "x"}}))
    r = _moderate()
    assert r["status"] == "unavailable" and r["error"] == f"http_{code}"
    assert _signal_codes(r) == ["ai_unavailable"]
    assert [s.level for s in rules.ai_signals(r, {"ai": {}})] == [rules.HOLD]


@pytest.mark.parametrize(
    "exc, error",
    [
        (requests.Timeout(), "timeout"),
        (requests.ConnectTimeout(), "timeout"),
        (requests.ReadTimeout(), "timeout"),
        (requests.ConnectionError("down"), "request_ConnectionError"),
        (requests.exceptions.SSLError("tls"), "request_SSLError"),
    ],
)
def test_timeouts_and_connection_errors_are_unavailable_hold(calls, exc, error):
    calls.respond(exc)
    r = _moderate()
    assert r["status"] == "unavailable" and r["error"] == error
    assert _signal_codes(r) == ["ai_unavailable"]


def test_unexpected_exception_is_unavailable_never_raised(calls):
    calls.respond(RuntimeError("boom"))
    r = _moderate()
    assert r["status"] == "unavailable" and r["error"] == "error_RuntimeError"
    _fails_closed(r)


def test_failure_of_a_later_batch_voids_the_whole_inspection(monkeypatch, calls):
    monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", "none")
    seen = {"n": 0}

    def respond(body):
        seen["n"] += 1
        return FakeResponse(200, chat(verdict(_n_images(body)))) if seen["n"] == 1 else FakeResponse(429, {})

    calls.respond_with(respond)
    r = _moderate([f"https://cdn.example.com/{i}.jpg" for i in range(6)])
    assert r["status"] == "unavailable" and r["error"] == "http_429"
    assert r["images_checked"] == 4 and r["images_expected"] == 6  # shortfall is visible
    _fails_closed(r)


def test_secrets_never_appear_in_results(monkeypatch, calls):
    monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", "none")
    for resp in (
        FakeResponse(401, {"error": {"message": f"bad key {_DUMMY_KEY}"}}),
        FakeResponse(200, chat("not json")),
        requests.ConnectionError(f"https://api.openai.com {_DUMMY_KEY}"),
    ):
        calls.respond(resp)
        assert _DUMMY_KEY not in json.dumps(_moderate())


def test_configuration_helper_reads_env(monkeypatch):
    assert ai.ai_reasoning_effort() is None
    monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", " None ")
    assert ai.ai_reasoning_effort() == "none"
    assert ai.REASONING_EFFORTS == {"none", "minimal", "low", "medium", "high", "xhigh", "max"}
