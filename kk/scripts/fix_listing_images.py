#!/usr/bin/env python3
"""
Replace generic seed photos with model-matching Wikimedia images.

  $env:DATABASE_URL = "postgresql://..."
  python kk/scripts/fix_listing_images.py
  python kk/scripts/fix_listing_images.py --seller-id 26
  python kk/scripts/fix_listing_images.py --only-unsplash
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _normalize_key(brand: str, model: str) -> str:
    return f"{brand.strip().lower()}|{model.strip().lower()}"


def main() -> int:
    p = argparse.ArgumentParser(description="Fix listing images to match brand/model.")
    p.add_argument("--seller-id", type=int, help="Only update listings from this seller")
    p.add_argument("--only-unsplash", action="store_true", help="Only fix listings using Unsplash URLs")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    root = _repo_root()
    scripts_dir = Path(__file__).resolve().parent
    for path in (str(root), str(scripts_dir)):
        if path not in sys.path:
            sys.path.insert(0, path)

    if not (os.environ.get("DATABASE_URL") or "").strip():
        print("FIX_IMAGES_ERR Set DATABASE_URL", file=sys.stderr)
        return 2

    os.environ.setdefault("APP_ENV", "development")

    from car_image_lookup import build_image_map
    from seed_50_listings_data import LISTINGS

    from kk import app_new as app_module
    from kk.models import Car, CarImage, db

    print("FIX_IMAGES fetching model-matching photos from Wikimedia...")
    image_map = build_image_map(LISTINGS, count=3)
    missing = [k for k, v in image_map.items() if not v]
    if missing:
        print(f"FIX_IMAGES_WARN no_images_for={missing[:10]}{'...' if len(missing)>10 else ''}")

    app = app_module.app
    updated_cars = 0
    with app.app_context():
        q = Car.query.filter_by(is_active=True)
        if args.seller_id:
            q = q.filter_by(seller_id=args.seller_id)

        for car in q.all():
            key = _normalize_key(car.brand or "", car.model or "")
            urls = image_map.get(key) or []
            if not urls:
                continue

            if args.only_unsplash:
                existing = CarImage.query.filter_by(car_id=car.id).all()
                if not existing:
                    continue
                if not any("unsplash.com" in (img.image_url or "") for img in existing):
                    continue
            else:
                existing = CarImage.query.filter_by(car_id=car.id).all()

            if args.dry_run:
                print(f"DRY_RUN car={car.id} {car.brand} {car.model} -> {len(urls)} images")
                updated_cars += 1
                continue

            for img in existing:
                db.session.delete(img)
            db.session.flush()

            for order, url in enumerate(urls):
                if len(url) > 200:
                    continue
                db.session.add(
                    CarImage(
                        car_id=car.id,
                        image_url=url,
                        is_primary=(order == 0),
                        order=order,
                        kind="listing",
                    )
                )
            updated_cars += 1
            print(f"FIX_OK car={car.public_id} {car.brand} {car.model} images={len(urls)}")
            db.session.commit()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
