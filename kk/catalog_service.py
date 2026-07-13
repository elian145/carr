"""Vehicle catalog seed + helpers (brands / models / body types)."""

from __future__ import annotations

import json
import logging
from pathlib import Path

from .models import CatalogBodyType, CatalogBrand, CatalogVehicleModel, db
from .time_utils import utcnow

logger = logging.getLogger(__name__)

DEFAULT_BODY_TYPES = (
    "Sedan",
    "SUV",
    "Hatchback",
    "Coupe",
    "Convertible",
    "Wagon",
    "Pickup",
    "Van",
    "Minivan",
)


def catalog_json_path() -> Path:
    """Resolve assets/car_catalog.json from repo root."""
    here = Path(__file__).resolve().parent
    candidates = [
        here.parent / "assets" / "car_catalog.json",
        Path.cwd() / "assets" / "car_catalog.json",
    ]
    for p in candidates:
        if p.is_file():
            return p
    return candidates[0]


def load_catalog_json(path: Path | None = None) -> dict:
    p = path or catalog_json_path()
    with open(p, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("car_catalog.json must be an object")
    return data


def seed_catalog(*, force: bool = False, include_body_types: bool = True) -> dict:
    """
    Upsert brands/models from assets/car_catalog.json.
    If the catalog already has brands and force is False, only fills body types when empty.
    """
    brand_count = CatalogBrand.query.count()
    seeded_brands = 0
    seeded_models = 0
    updated_brands = 0
    updated_models = 0
    skipped = False

    if brand_count > 0 and not force:
        skipped = True
    else:
        data = load_catalog_json()
        brands = data.get("brands") or []
        models_map = data.get("models") or {}
        if not isinstance(brands, list):
            brands = list(models_map.keys()) if isinstance(models_map, dict) else []

        for idx, raw_name in enumerate(brands):
            name = str(raw_name or "").strip()
            if not name:
                continue
            brand = CatalogBrand.query.filter_by(name=name).first()
            if not brand:
                brand = CatalogBrand(
                    name=name,
                    is_active=True,
                    sort_order=idx,
                    created_at=utcnow(),
                    updated_at=utcnow(),
                )
                db.session.add(brand)
                db.session.flush()
                seeded_brands += 1
            else:
                brand.sort_order = idx
                brand.is_active = True
                brand.updated_at = utcnow()
                updated_brands += 1

            model_names = models_map.get(name) if isinstance(models_map, dict) else None
            if not isinstance(model_names, list):
                continue
            for midx, raw_model in enumerate(model_names):
                mname = str(raw_model or "").strip()
                if not mname:
                    continue
                row = CatalogVehicleModel.query.filter_by(
                    brand_id=brand.id, name=mname
                ).first()
                if not row:
                    db.session.add(
                        CatalogVehicleModel(
                            brand_id=brand.id,
                            name=mname,
                            is_active=True,
                            sort_order=midx,
                            created_at=utcnow(),
                            updated_at=utcnow(),
                        )
                    )
                    seeded_models += 1
                else:
                    row.sort_order = midx
                    row.is_active = True
                    row.updated_at = utcnow()
                    updated_models += 1

    body_seeded = 0
    body_updated = 0
    if include_body_types:
        existing_bodies = CatalogBodyType.query.count()
        if existing_bodies == 0 or force:
            for bidx, bname in enumerate(DEFAULT_BODY_TYPES):
                row = CatalogBodyType.query.filter_by(name=bname).first()
                if not row:
                    db.session.add(
                        CatalogBodyType(
                            name=bname,
                            is_active=True,
                            sort_order=bidx,
                            created_at=utcnow(),
                            updated_at=utcnow(),
                        )
                    )
                    body_seeded += 1
                else:
                    row.sort_order = bidx
                    row.is_active = True
                    row.updated_at = utcnow()
                    body_updated += 1

    db.session.commit()
    return {
        "skipped_brand_seed": skipped,
        "brands_created": seeded_brands,
        "brands_updated": updated_brands,
        "models_created": seeded_models,
        "models_updated": updated_models,
        "body_types_created": body_seeded,
        "body_types_updated": body_updated,
        "totals": {
            "brands": CatalogBrand.query.count(),
            "models": CatalogVehicleModel.query.count(),
            "body_types": CatalogBodyType.query.count(),
        },
        "source": str(catalog_json_path()),
    }
