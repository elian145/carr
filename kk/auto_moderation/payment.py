"""Listing-payment eligibility for automatic approval.

What CarNet has today
---------------------
Nothing charges for a listing. There is no payment gateway, no in-app
purchase, no listing-payment ledger, no free-allowance counter and no payment
status on ``Car`` (``docs/PAYMENTS.md``: purchase payments are off-platform;
``featured_listing_price`` / ``dealer_subscription_price`` are informational
reference values only). So in this release a listing is "free": there is no
payment to verify, and the ``listing_payment_required`` setting is OFF.

What this module guarantees
---------------------------
* Payment is NEVER inferred, defaulted or accepted from client input. The only
  thing that can mark a listing as paid / free-eligible is a *server-side
  verifier* registered with :func:`register_payment_verifier` by the code that
  owns the ledger.
* With ``listing_payment_required`` ON and no verifier registered (the only
  state reachable in this release) every new listing is sent to NEEDS_REVIEW.
* A verifier that raises, or answers with anything other than an explicit,
  well-formed proof for THIS listing, can never approve: an exception is a HOLD
  (service problem, retried), any other answer is NEEDS_REVIEW.
* The check is re-run at apply time under the subject lock (the rules are
  rebuilt from fresh facts), so a refund / revoked allowance between decision
  and publication blocks the approval.

Smallest safe integration for real paid / free-allowance listings
-----------------------------------------------------------------
1. A ledger table written ONLY by the payment provider's server-side webhook
   or an admin action (never by the listing/edit endpoints), e.g.
   ``listing_payment(id, car_id, seller_id, kind['paid'|'free_allowance'],
   amount, currency, provider, provider_ref UNIQUE, status, created_at)``.
2. ``verifier(car_id, seller_id)`` that returns a proof only for a ``succeeded``
   ledger row for that very car, consumed at most once.
3. ``register_payment_verifier(verifier)`` at app start, then set
   ``listing_payment_required`` ON.
Edits of an already-published listing never re-check payment (they were
covered when the listing was approved).
"""

from __future__ import annotations

import logging
from typing import Any, Callable

logger = logging.getLogger(__name__)

VERIFIED_KINDS = frozenset({"paid", "free_allowance"})

# verifier(car_id, seller_id) -> {"status": "paid"|"free_allowance",
#                                 "car_id": <same car>, "reference": str} | None
Verifier = Callable[[int, "int | None"], "dict[str, Any] | None"]

_verifier: Verifier | None = None


def register_payment_verifier(fn: Verifier | None) -> None:
    """Install (or, with ``None``, remove) the server-side verifier."""
    global _verifier
    _verifier = fn


def verifier_registered() -> bool:
    return _verifier is not None


def assess(subject_type: str, car_id: int, seller_id: int | None, settings: dict) -> dict[str, Any]:
    """Payment facts for the rules. ``status`` is one of:

    ``not_required``  deployment does not meter listings / subject is an edit
    ``verified``      the registered verifier proved payment or an allowance
    ``unverified``    payment is required and cannot be proven (-> review)
    ``error``         the verifier failed (-> hold; never an approval)
    """
    required = bool(settings.get("listing_payment_required")) and subject_type == "listing"
    if not required:
        return {"required": False, "status": "not_required"}
    if _verifier is None:
        return {"required": True, "status": "unverified", "reason": "no_verifier"}
    try:
        proof = _verifier(int(car_id), seller_id)
    except Exception as exc:  # a broken ledger must never read as "paid"
        logger.warning("payment verifier failed: %s", type(exc).__name__)
        return {"required": True, "status": "error", "reason": type(exc).__name__}
    if (
        isinstance(proof, dict)
        and proof.get("status") in VERIFIED_KINDS
        and proof.get("car_id") == int(car_id)
        and isinstance(proof.get("reference"), str)
        and proof["reference"].strip()
    ):
        return {
            "required": True,
            "status": "verified",
            "kind": proof["status"],
            "reference": proof["reference"].strip()[:100],
        }
    return {"required": True, "status": "unverified", "reason": "no_valid_proof"}
