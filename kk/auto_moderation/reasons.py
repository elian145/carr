"""Human-readable wording for moderation reason codes (admin dashboard only).

The reason ``code`` stays the stable, machine-readable identifier stored on
every run (rules / engine / stats / alerts key off it). This module only adds
presentation: a short ``label`` and a plain-language ``explanation`` for the
administrator reviewing the listing. It is applied when a run is SERIALISED for
the admin API, so wording can be improved without touching stored decisions and
old runs get it too.

Nothing here is ever shown to sellers, and no wording mentions prompts, models
or provider internals.
"""

from __future__ import annotations

#: code -> (short label, one-sentence explanation for the reviewing admin)
_CATALOG: dict[str, tuple[str, str]] = {
    # --- Cross-field consistency -------------------------------------------
    "ev_with_combustion_engine": (
        "Electric car with a combustion engine",
        "The listing says the car is purely electric, but it also lists an engine size and/or "
        "cylinders, which a battery-electric car does not have. Check whether the fuel type is "
        "wrong (e.g. it is a hybrid or range-extender) or the engine figures were copied from "
        "another model.",
    ),
    "ev_powertrain_unconfirmed": (
        "Electric car with engine figures and hybrid wording",
        "The fuel / engine type says purely electric and an engine size and/or cylinders are listed, "
        "while the seller's text mentions a hybrid or range extender. Seller text is not proof of the "
        "powertrain, so a person must confirm it: a genuine range-extender or plug-in hybrid should "
        "have its fuel type set to match, otherwise the engine figures or the fuel type are wrong.",
    ),
    "high_mileage_for_year": (
        "Unusually high mileage for the model year",
        "The odometer is far above what a car of this model year normally covers. This is a soft "
        "signal only: taxis, fleet and long-distance cars can legitimately do this. Compare with "
        "the photos and description.",
    ),
    "engine_displacement_cylinders_mismatch": (
        "Engine size and cylinders do not fit together",
        "The engine size divided by the number of cylinders is outside what real engines have. "
        "One of the two figures is probably mistyped.",
    ),
    "engine_displacement_out_of_range": (
        "Engine size is not realistic",
        "The engine size is outside the range of any road vehicle. It is probably mistyped or in "
        "the wrong unit (litres vs cc).",
    ),
    "cylinder_count_out_of_range": (
        "Cylinder count is not realistic",
        "The cylinder count is negative or higher than any road vehicle has. It is probably "
        "mistyped.",
    ),
    "new_but_old_year": (
        "Listed as New with an old model year",
        "The seller marked the car as New, but its model year is more than a year old. Check "
        "whether the condition or the year is wrong.",
    ),
    "new_with_mileage": (
        "Listed as New with mileage",
        "The seller marked the car as New, but the odometer is above what a new car normally "
        "shows. Check whether the condition is wrong.",
    ),
    "used_zero_mileage": (
        "Used car with 0 km",
        "The car is listed as used with an older model year but 0 km. The mileage may simply "
        "have been left empty.",
    ),
    # --- Values ---------------------------------------------------------------
    "missing_field": ("Required detail missing", "A required listing detail is empty or a placeholder."),
    "year_out_of_range": ("Model year out of range", "The model year is outside the accepted range."),
    "mileage_out_of_range": (
        "Mileage out of range",
        "The mileage is negative or above the accepted maximum.",
    ),
    "price_invalid": ("Invalid price", "The price is missing, zero or not a number."),
    "price_out_of_range": (
        "Price outside the expected range",
        "The price is far below or above what is normal for the currency.",
    ),
    "unknown_currency": ("Unknown currency", "The currency has no configured price range to check against."),
    "vin_invalid": ("Invalid VIN format", "The VIN is not a valid 17-character VIN."),
    # --- Text -----------------------------------------------------------------
    "scam_language": ("Possible scam wording", "The text contains wording typical of scams."),
    "prohibited_content": ("Prohibited wording", "The text mentions prohibited goods or services."),
    "non_car_content": ("Text unrelated to cars", "The text looks like it is about something other than a car."),
    "repeated_characters": ("Spam-like text", "The description repeats the same character many times."),
    "excessive_caps": ("Excessive capital letters", "Most of the description is in capital letters."),
    "repetitive_text": ("Repetitive text", "The description repeats the same words over and over."),
    "description_too_long": ("Very long description", "The description is unusually long."),
    "contact_in_description": (
        "Contact details in the description",
        "The description contains a phone number, e-mail or link.",
    ),
    # --- Media ----------------------------------------------------------------
    "media_processing": ("Photos still processing", "Uploaded media is not finished yet; nothing is judged until it is."),
    "media_failed": ("Photo upload failed", "At least one photo or video failed to process."),
    "too_few_photos": ("Too few photos", "The listing has fewer photos than required."),
    "media_missing": ("Photo missing", "A photo the seller attached is missing or empty."),
    "videos_not_inspected": ("Video not inspected", "Videos are not checked automatically; a person must look."),
    "cover_invalid": ("Cover photo problem", "The listing does not have exactly one cover photo."),
    "cover_mismatch": ("Cover photo mismatch", "The photo set as cover is not the stored cover."),
    "low_resolution": ("Low-resolution photo", "At least one photo is smaller than the minimum size."),
    # --- Duplicates / seller --------------------------------------------------
    "duplicate_listing": ("Duplicate of another listing", "The seller already has a near-identical listing."),
    "repeated_description": ("Description reused", "The same description is used on another of the seller's listings."),
    "vin_reused_own": ("VIN reused by the same seller", "The VIN is already on another listing of this seller."),
    "vin_other_seller": ("VIN used by another seller", "The VIN is already on another seller's listing."),
    "high_posting_rate": ("Many listings in 24 hours", "The seller posted unusually many listings in the last day."),
    "seller_missing": ("Seller account missing", "The seller's account no longer exists."),
    "seller_inactive": ("Seller account restricted", "The seller's account is inactive."),
    "seller_not_verified": ("Seller phone not verified", "The seller has not verified a phone number."),
    "seller_open_reports": ("Seller has open reports", "There are unresolved reports about this seller or their listings."),
    "seller_abuse_history": ("Seller moderation history", "The seller has had listings rejected or hidden before."),
    "seller_unproven": ("New or unproven seller", "The seller has no human-approved listings yet."),
    "pinned_manual_review": ("Pinned to manual review", "An administrator pinned this listing to manual review."),
    # --- Payment / revision -----------------------------------------------------
    "payment_unverifiable": ("Payment not verified", "Payment could not be confirmed for this listing."),
    "payment_check_unavailable": ("Payment check unavailable", "The payment verifier could not be reached."),
    "payment_verified": ("Payment verified", "Payment was confirmed (informational)."),
    "no_effective_changes": ("Edit changes nothing", "The submitted edit does not change the listing."),
    "identity_changed": ("Vehicle identity edited", "Brand, model, year or VIN was changed on a published listing."),
    "large_price_change": ("Large price change", "The price changed by more than the configured percentage."),
    # --- AI (advisory) ----------------------------------------------------------
    "ai_flagged": ("Flagged by the automatic content check", "The automatic text/photo check raised a concern."),
    "ai_not_configured": ("Automatic content check not configured", "No provider is configured, so photos could not be checked."),
    "ai_unavailable": ("Automatic content check unavailable", "The provider could not be reached; the listing is held."),
    "ai_uncertain": ("Automatic content check inconclusive", "The check could not reach a clear answer."),
    "ai_not_run": ("Automatic content check not run", "The check did not run for this content."),
    "ai_low_confidence": ("Low confidence", "The automatic check was not confident enough."),
    "ai_image_coverage_incomplete": ("Not every photo was checked", "Some photos were not inspected, so the listing needs a person."),
    "ai_cover_not_checked": ("Cover photo not checked", "The cover photo was not inspected."),
    "ai_images_not_inspected": ("Photos not inspected", "Skipped because rules already flag the listing (informational)."),
    "engine_error": ("Internal error", "The check failed internally and will be retried."),
    "decision_expired": ("Decision expired", "The decision was too old to apply and is re-evaluated."),
}


def label_for(code: str | None) -> str:
    code = code or ""
    entry = _CATALOG.get(code)
    return entry[0] if entry else code.replace("_", " ").strip().capitalize()


def explanation_for(code: str | None) -> str | None:
    entry = _CATALOG.get(code or "")
    return entry[1] if entry else None


def enrich(reason: dict) -> dict:
    """A copy of a stored reason with ``label`` and ``message`` added."""
    out = dict(reason)
    code = reason.get("code")
    out["label"] = label_for(code)
    msg = explanation_for(code)
    if msg:
        out["message"] = msg
    return out
