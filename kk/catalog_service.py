"""Vehicle catalog seed + helpers (brands / models / trims / body types)."""

from __future__ import annotations

import json
import logging
from pathlib import Path

from .models import CatalogBodyType, CatalogBrand, CatalogTrim, CatalogVehicleModel, db
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


def _seed_trims_for_model(model_row: CatalogVehicleModel, trim_names: list, *, force: bool) -> tuple[int, int]:
    created = 0
    updated = 0
    if CatalogTrim.query.filter_by(model_id=model_row.id).count() > 0 and not force:
        return 0, 0
    for tidx, raw_trim in enumerate(trim_names):
        tname = str(raw_trim or "").strip()
        if not tname:
            continue
        row = CatalogTrim.query.filter_by(model_id=model_row.id, name=tname).first()
        if not row:
            db.session.add(
                CatalogTrim(
                    model_id=model_row.id,
                    name=tname,
                    is_active=True,
                    sort_order=tidx,
                    created_at=utcnow(),
                    updated_at=utcnow(),
                )
            )
            created += 1
        else:
            row.sort_order = tidx
            row.is_active = True
            row.updated_at = utcnow()
            updated += 1
    return created, updated


def seed_catalog(*, force: bool = False, include_body_types: bool = True) -> dict:
    """
    Upsert brands/models/trims from assets/car_catalog.json.
    If brands already exist and force is False, still fills empty trims + body types.
    """
    brand_count = CatalogBrand.query.count()
    seeded_brands = 0
    seeded_models = 0
    seeded_trims = 0
    updated_brands = 0
    updated_models = 0
    updated_trims = 0
    skipped = False

    data = load_catalog_json()
    brands = data.get("brands") or []
    models_map = data.get("models") or {}
    trims_map = data.get("trimsByBrandModel") or {}
    if not isinstance(brands, list):
        brands = list(models_map.keys()) if isinstance(models_map, dict) else []

    if brand_count > 0 and not force:
        skipped = True
    else:
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
            brand_trims = trims_map.get(name) if isinstance(trims_map, dict) else None
            for midx, raw_model in enumerate(model_names):
                mname = str(raw_model or "").strip()
                if not mname:
                    continue
                row = CatalogVehicleModel.query.filter_by(
                    brand_id=brand.id, name=mname
                ).first()
                if not row:
                    row = CatalogVehicleModel(
                        brand_id=brand.id,
                        name=mname,
                        is_active=True,
                        sort_order=midx,
                        created_at=utcnow(),
                        updated_at=utcnow(),
                    )
                    db.session.add(row)
                    db.session.flush()
                    seeded_models += 1
                else:
                    row.sort_order = midx
                    row.is_active = True
                    row.updated_at = utcnow()
                    updated_models += 1

                if isinstance(brand_trims, dict):
                    trim_names = brand_trims.get(mname)
                    if isinstance(trim_names, list):
                        c, u = _seed_trims_for_model(row, trim_names, force=True)
                        seeded_trims += c
                        updated_trims += u

    # Fill trims when brands already present but trims empty (or force)
    if skipped or force:
        if isinstance(trims_map, dict) and (CatalogTrim.query.count() == 0 or force):
            for brand_name, models in trims_map.items():
                if not isinstance(models, dict):
                    continue
                brand = CatalogBrand.query.filter_by(name=str(brand_name)).first()
                if not brand:
                    continue
                for model_name, trim_names in models.items():
                    if not isinstance(trim_names, list):
                        continue
                    row = CatalogVehicleModel.query.filter_by(
                        brand_id=brand.id, name=str(model_name)
                    ).first()
                    if not row:
                        continue
                    c, u = _seed_trims_for_model(row, trim_names, force=force)
                    seeded_trims += c
                    updated_trims += u

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
        "trims_created": seeded_trims,
        "trims_updated": updated_trims,
        "body_types_created": body_seeded,
        "body_types_updated": body_updated,
        "totals": {
            "brands": CatalogBrand.query.count(),
            "models": CatalogVehicleModel.query.count(),
            "trims": CatalogTrim.query.count(),
            "body_types": CatalogBodyType.query.count(),
        },
        "source": str(catalog_json_path()),
    }
