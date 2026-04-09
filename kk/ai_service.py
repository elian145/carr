import json
import os
import re
import logging
from datetime import datetime
from typing import Any, Dict, Optional

import requests

logger = logging.getLogger(__name__)

def _env() -> str:
    return (os.environ.get("APP_ENV") or os.environ.get("FLASK_ENV") or "production").strip().lower()


class CarAnalysisService:
    """
	Placeholder car analysis service.

	All license-plate blurring functionality has been removed.
    """

    def __init__(self):
        self.initialized: bool = False
        self._initialize_models()

    def _initialize_models(self) -> None:
        """
        Initialize AI components.
        """
        try:
            self.initialized = True
            logger.info("AI service initialized.")
        except Exception as e:
            self.initialized = False
            logger.error(f"Failed to initialize AI service: {e}")

    def analyze_car_image(self, image_path: str) -> Dict:
        """
        Analyze a car image and extract vehicle information.

        This project currently returns a stable placeholder payload; callers rely on its shape.
        """
        try:
            return {
                "processed_image_path": image_path,
                "car_info": {
                    "color": "white",
                    "body_type": "sedan",
                    "condition": "good",
                    "doors": 4,
                },
                "brand_model": {
                    "brand": "toyota",
                    "model": "camry",
                    "year_range": "2020-2023",
                    "confidence": 0.75,
                },
                "confidence_scores": {
                    "color": 0.8,
                    "body_type": 0.6,
                    "condition": 0.7,
                    "brand_model": 0.75,
                },
                "analysis_timestamp": str(datetime.now()),
            }
        except Exception as e:
            logger.exception("Error analyzing car image")
            if _env() in ("development", "testing"):
                return {"error": str(e)}
            return {"error": "analysis_failed"}


# Singleton used across kk scripts and apps
car_analysis_service = CarAnalysisService()


def _openai_error_message(status_code: int, body: str) -> str:
    """Turn OpenAI HTTP errors into short, user-facing text for the mobile app."""
    try:
        data = json.loads(body)
        err = data.get("error") if isinstance(data, dict) else None
        if isinstance(err, dict):
            code = (err.get("code") or "").strip()
            typ = (err.get("type") or "").strip()
            msg = (err.get("message") or "").strip()
            if status_code == 429:
                if code == "insufficient_quota" or typ == "insufficient_quota":
                    return (
                        "OpenAI quota or billing exhausted. Add payment method or credits at "
                        "platform.openai.com/account/billing — then retry."
                    )
                return (
                    "OpenAI rate limit (429). Wait a minute and retry, or upgrade your API tier."
                )
            if status_code == 401:
                return "OpenAI rejected the API key. Set a valid OPENAI_API_KEY on the server."
            if msg:
                return f"OpenAI: {msg[:200]}"
    except (json.JSONDecodeError, TypeError):
        pass
    if status_code == 429:
        return (
            "OpenAI returned 429 (quota or rate limit). Check billing and limits at "
            "platform.openai.com."
        )
    return "AI provider returned an error. Check server logs and OPENAI_API_KEY."


def _strip_json_fence(text: str) -> str:
    s = (text or "").strip()
    if s.startswith("```"):
        s = re.sub(r"^```(?:json)?\s*", "", s, flags=re.IGNORECASE)
        s = re.sub(r"\s*```\s*$", "", s)
    return s.strip()


def _coerce_specs_dict(data: Dict[str, Any]) -> Dict[str, Any]:
    """Normalize LLM output to stable API-style enums used by the Flutter app."""
    out: Dict[str, Any] = {}

    tr = str(data.get("transmission") or "automatic").lower()
    out["transmission"] = "manual" if "manual" in tr else "automatic"

    drv = str(data.get("drivetrain") or "fwd").lower()
    if drv in ("4x4", "4_x_4"):
        drv = "4wd"
    if drv not in ("fwd", "rwd", "awd", "4wd"):
        drv = "fwd"
    out["drivetrain"] = drv

    body = str(data.get("body_type") or "sedan").lower()
    if body not in ("sedan", "suv", "hatchback", "coupe", "pickup", "van"):
        body = "sedan"
    out["body_type"] = body

    fuel = str(data.get("fuel_type") or data.get("engine_type") or "gasoline").lower()
    if fuel in ("petrol", "petroleum", "gas"):
        fuel = "gasoline"
    if fuel == "phev":
        fuel = "hybrid"
    if fuel not in ("gasoline", "diesel", "electric", "hybrid"):
        fuel = "gasoline"
    out["fuel_type"] = fuel
    out["engine_type"] = str(data.get("engine_type") or fuel).lower()
    if out["engine_type"] not in ("gasoline", "diesel", "electric", "hybrid"):
        out["engine_type"] = out["fuel_type"]

    esl = data.get("engine_size_liters")
    if esl is not None and esl != "":
        try:
            v = float(esl)
            if 0.3 <= v <= 20.0:
                out["engine_size_liters"] = round(v, 1)
        except (TypeError, ValueError):
            pass

    cc = data.get("cylinder_count")
    if cc is not None and cc != "":
        try:
            c = int(float(cc))
            if 1 <= c <= 16:
                out["cylinder_count"] = c
        except (TypeError, ValueError):
            pass

    st = data.get("seating")
    if st is not None and st != "":
        try:
            n = int(float(st))
            if 1 <= n <= 15:
                out["seating"] = n
        except (TypeError, ValueError):
            pass

    fe = data.get("fuel_economy")
    if fe is not None:
        s = str(fe).strip()
        if s:
            out["fuel_economy"] = s[:120]

    notes = data.get("notes")
    if notes is not None:
        out["notes"] = str(notes).strip()[:500]

    return out


def suggest_car_specs_from_ymm(
    year: int,
    brand: str,
    model: str,
    trim: str,
    *,
    market_hint: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Use OpenAI (JSON mode) to propose vehicle specs when the Car API has no match.

    Requires OPENAI_API_KEY. Optional: OPENAI_MODEL (default gpt-4o-mini).
    """
    key = (os.environ.get("OPENAI_API_KEY") or "").strip()
    if not key:
        return {
            "error": "AI spec suggestion is not configured. Set OPENAI_API_KEY on the server.",
            "configured": False,
        }

    model = (os.environ.get("OPENAI_MODEL") or "gpt-4o-mini").strip()
    market = (market_hint or "").strip() or "unspecified region — use the most common global configuration"

    system = (
        "You are an automotive data assistant. Given year, brand, model, and trim, "
        "propose the most likely factory technical specs for that exact variant. "
        "If uncertain, pick the most common configuration and say so in notes. "
        "Respond with a single JSON object only (no markdown), keys: "
        "transmission (automatic or manual), drivetrain (fwd, rwd, awd, or 4wd), "
        "body_type (sedan, suv, hatchback, coupe, pickup, or van), "
        "fuel_type (gasoline, diesel, electric, or hybrid), "
        "engine_type (same vocabulary as fuel_type for piston engines), "
        "engine_size_liters (number or null), cylinder_count (integer or null), "
        "seating (integer or null), fuel_economy (short string or null, e.g. combined L/100km or MPG), "
        "notes (one short sentence about confidence or assumptions)."
    )
    user = (
        f"year={year}, brand={brand}, model={model}, trim={trim}, market_hint={market}"
    )

    try:
        resp = requests.post(
            "https://api.openai.com/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
            },
            json={
                "model": model,
                "temperature": 0.2,
                "response_format": {"type": "json_object"},
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
            },
            timeout=90,
        )
        if resp.status_code != 200:
            logger.warning("OpenAI specs HTTP %s: %s", resp.status_code, resp.text[:500])
            return {
                "error": _openai_error_message(resp.status_code, resp.text or ""),
                "configured": True,
            }
        payload = resp.json()
        choices = payload.get("choices") or []
        if not choices:
            return {"error": "Empty AI response", "configured": True}
        content = (choices[0].get("message") or {}).get("content") or ""
        raw = json.loads(_strip_json_fence(content))
        if not isinstance(raw, dict):
            return {"error": "AI returned non-object JSON", "configured": True}
        specs = _coerce_specs_dict(raw)
        specs["source"] = "openai"
        specs["model"] = model
        return specs
    except json.JSONDecodeError as e:
        logger.warning("AI specs JSON decode: %s", e)
        return {"error": "Could not parse AI response as JSON", "configured": True}
    except requests.RequestException as e:
        logger.warning("AI specs request failed: %s", e)
        return {"error": "Network error calling AI provider", "configured": True}
    except Exception as e:
        logger.exception("AI specs unexpected error")
        if _env() in ("development", "testing"):
            return {"error": str(e), "configured": True}
        return {"error": "AI suggestion failed", "configured": True}

