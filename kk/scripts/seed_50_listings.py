#!/usr/bin/env python3
"""
Seed 50 realistic car listings with real photos.

Direct database mode (recommended for production Postgres):
  $env:DATABASE_URL = "postgresql://..."
  python kk/scripts/seed_50_listings.py

API mode (uses JWT login + image URL attach):
  python kk/scripts/seed_50_listings.py --api-base https://carr-5hrm.onrender.com --username USER --password PASS
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _http_json(
    method: str,
    url: str,
    *,
    data: dict | None = None,
    token: str | None = None,
    timeout: int = 120,
) -> tuple[int, dict]:
    headers = {"Accept": "application/json", "User-Agent": "CarListingSeed/1.0"}
    body = None
    if data is not None:
        body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"message": raw or str(e)}
        return e.code, payload


def _pick_images(
    item: dict,
    pool: list[str],
    index: int,
    *,
    image_map: dict[str, list[str]] | None = None,
    count: int = 3,
) -> list[str]:
    explicit = item.get("images")
    if isinstance(explicit, list) and explicit:
        return [str(u) for u in explicit[:count]]

    brand = str(item.get("brand") or "").strip().lower()
    model = str(item.get("model") or "").strip().lower()
    key = f"{brand}|{model}"
    if image_map and image_map.get(key):
        return image_map[key][:count]

    if not pool:
        return []
    return [pool[(index + j) % len(pool)] for j in range(count)]


def _build_car_payload(item: dict, *, city: str, region_specs: str) -> dict:
    brand = str(item["brand"]).strip().lower()
    model = str(item["model"]).strip()
    trim = str(item.get("trim") or "base").strip()
    year = int(item["year"])
    fuel = str(item.get("fuel_type") or "gasoline").strip().lower()
    payload = {
        "title": f"{brand.title()} {model} {trim}".strip(),
        "brand": brand,
        "model": model,
        "trim": trim,
        "year": year,
        "price": float(item["price"]),
        "mileage": int(item["mileage"]),
        "condition": str(item.get("condition") or "used").lower(),
        "transmission": str(item.get("transmission") or "automatic").lower(),
        "engine_type": fuel,
        "fuel_type": fuel,
        "color": str(item.get("color") or "white").lower(),
        "body_type": str(item.get("body_type") or "sedan").lower(),
        "seating": int(item.get("seating") or 5),
        "drive_type": str(item.get("drive_type") or "fwd").lower(),
        "location": city,
        "region_specs": region_specs,
        "title_status": "clean",
        "currency": "USD",
        "status": "active",
        "description": item.get("description"),
    }
    if item.get("cylinder_count") is not None:
        payload["cylinder_count"] = int(item["cylinder_count"])
    if item.get("engine_size") is not None:
        payload["engine_size"] = float(item["engine_size"])
    return {k: v for k, v in payload.items() if v is not None}


def _load_image_map(listings: list[dict]) -> dict[str, list[str]]:
    try:
        from car_image_lookup import build_image_map

        print("SEED fetching model-matching photos from Wikimedia...")
        return build_image_map(listings, count=3)
    except Exception as exc:
        print(f"SEED_WARN image_lookup_failed: {exc}")
        return {}


def seed_via_api(
    api_base: str,
    username: str,
    password: str,
    *,
    dry_run: bool = False,
) -> int:
    from seed_50_listings_data import CITIES, IMAGE_POOL, LISTINGS, REGION_SPECS

    image_map = _load_image_map(LISTINGS)

    base = api_base.rstrip("/")
    status, body = _http_json(
        "POST",
        f"{base}/api/auth/login",
        data={"username": username, "password": password},
    )
    if status != 200:
        print(f"SEED_ERR login_failed status={status} body={body}", file=sys.stderr)
        return 1
    token = body.get("access_token") or body.get("token")
    if not token:
        print("SEED_ERR no_token_in_login_response", file=sys.stderr)
        return 1
    user = body.get("user") or {}
    print(f"SEED_LOGIN_OK user={user.get('username')} verified={user.get('is_verified')} admin={user.get('is_admin')}")

    created = 0
    for i, item in enumerate(LISTINGS):
        city = CITIES[i % len(CITIES)]
        region = REGION_SPECS[i % len(REGION_SPECS)]
        payload = _build_car_payload(item, city=city, region_specs=region)
        if dry_run:
            print(f"DRY_RUN create {payload['title']} @ {city}")
            continue

        status, resp = _http_json("POST", f"{base}/api/cars", data=payload, token=token)
        if status != 201:
            print(f"SEED_ERR create_failed idx={i} status={status} body={resp}", file=sys.stderr)
            return 1
        car = resp.get("car") or {}
        car_id = car.get("id")
        if not car_id:
            print(f"SEED_ERR missing_car_id idx={i}", file=sys.stderr)
            return 1

        images = _pick_images(item, IMAGE_POOL, i, image_map=image_map, count=3)
        status, resp = _http_json(
            "POST",
            f"{base}/api/cars/{car_id}/images/attach",
            data={"urls": images},
            token=token,
        )
        if status not in (200, 201):
            print(f"SEED_ERR attach_images idx={i} status={status} body={resp}", file=sys.stderr)
            return 1

        created += 1
        print(f"SEED_OK [{created}/{len(LISTINGS)}] {payload['title']} ({city}) images={len(images)}")

    print(f"SEED_DONE api created={created}")
    return 0


def _resolve_seller_id(User, db) -> int:
    """Prefer admin, then any verified user, then any user with listings."""
    from kk.models import Car

    admin = User.query.filter_by(is_admin=True, is_active=True).order_by(User.id.asc()).first()
    if admin:
        return int(admin.id)
    verified = User.query.filter_by(is_verified=True, is_active=True).order_by(User.id.asc()).first()
    if verified:
        return int(verified.id)
    row = (
        db.session.query(Car.seller_id)
        .filter(Car.seller_id.isnot(None))
        .group_by(Car.seller_id)
        .order_by(db.func.count(Car.id).desc())
        .first()
    )
    if row and row[0]:
        return int(row[0])
    any_user = User.query.filter_by(is_active=True).order_by(User.id.asc()).first()
    if any_user:
        return int(any_user.id)
    raise RuntimeError("No active user found to assign as seller_id")


def seed_via_db(*, dry_run: bool = False, seller_phone: str | None = None) -> int:
    from seed_50_listings_data import CITIES, IMAGE_POOL, LISTINGS, REGION_SPECS

    image_map = _load_image_map(LISTINGS)

    from kk import app_new as app_module
    from kk.models import Car, CarImage, User, db

    app = app_module.app
    with app.app_context():
        if seller_phone:
            digits = "".join(ch for ch in seller_phone if ch.isdigit())
            variants = {digits}
            if len(digits) == 10:
                variants.add("0" + digits)
            if len(digits) == 11 and digits.startswith("0"):
                variants.add(digits[1:])
            seller = User.query.filter(User.phone_number.in_(list(variants))).first()
            if not seller:
                print(f"SEED_ERR seller_not_found phone={seller_phone}", file=sys.stderr)
                return 1
            seller_id = int(seller.id)
            print(f"SEED_SELLER phone={seller.phone_number} id={seller_id} username={seller.username!r}")
        else:
            seller_id = _resolve_seller_id(User, db)
            seller = User.query.get(seller_id)
            print(f"SEED_SELLER auto id={seller_id} username={getattr(seller, 'username', None)!r}")

        created = 0
        for i, item in enumerate(LISTINGS):
            city = CITIES[i % len(CITIES)]
            region = REGION_SPECS[i % len(REGION_SPECS)]
            payload = _build_car_payload(item, city=city, region_specs=region)
            brand = payload["brand"]
            model = payload["model"]
            title = payload["title"]

            if dry_run:
                print(f"DRY_RUN db insert {title} @ {city}")
                continue

            car = Car(
                seller_id=seller_id,
                title=title,
                title_status="clean",
                brand=brand,
                model=model,
                trim=payload["trim"],
                year=int(payload["year"]),
                mileage=int(payload["mileage"]),
                engine_type=payload["engine_type"],
                fuel_type=payload["fuel_type"],
                transmission=payload["transmission"],
                drive_type=payload["drive_type"],
                condition=payload["condition"],
                body_type=payload["body_type"],
                price=float(payload["price"]),
                location=city,
                seating=int(payload["seating"]),
                status="active",
                description=payload.get("description"),
                color=payload.get("color"),
                region_specs=region,
                cylinder_count=payload.get("cylinder_count"),
                engine_size=payload.get("engine_size"),
                is_active=True,
            )
            db.session.add(car)
            db.session.flush()

            images = _pick_images(item, IMAGE_POOL, i, image_map=image_map, count=3)
            for order, url in enumerate(images):
                db.session.add(
                    CarImage(
                        car_id=car.id,
                        image_url=url,
                        is_primary=(order == 0),
                        order=order,
                        kind="listing",
                    )
                )
            created += 1
            print(f"SEED_OK [{created}/{len(LISTINGS)}] {title} ({city}) public_id={car.public_id}")

        if dry_run:
            db.session.rollback()
            print("SEED_DRY_RUN no_commit")
            return 0

        db.session.commit()
        total = Car.query.filter_by(is_active=True).count()
        print(f"SEED_DONE db created={created} active_listings_total={total}")
        return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Seed 50 realistic car listings.")
    p.add_argument("--api-base", help="Use REST API mode (e.g. https://carr-5hrm.onrender.com)")
    p.add_argument("--username", help="Login username/email/phone for API mode")
    p.add_argument("--password", help="Login password for API mode")
    p.add_argument("--seller-phone", help="Assign listings to this seller (DB mode only)")
    p.add_argument("--dry-run", action="store_true", help="Print actions without writing")
    args = p.parse_args()

    root = _repo_root()
    scripts_dir = Path(__file__).resolve().parent
    for path in (str(root), str(scripts_dir)):
        if path not in sys.path:
            sys.path.insert(0, path)

    os.environ.setdefault("APP_ENV", "development")

    if args.api_base:
        if not args.username or not args.password:
            print("SEED_ERR API mode requires --username and --password", file=sys.stderr)
            return 2
        return seed_via_api(
            args.api_base,
            args.username,
            args.password,
            dry_run=args.dry_run,
        )

    if not (os.environ.get("DATABASE_URL") or "").strip():
        print(
            "SEED_ERR Set DATABASE_URL for direct DB seeding, or pass --api-base with credentials.\n"
            "  PowerShell: $env:DATABASE_URL = \"postgresql://...\"\n"
            "  python kk/scripts/seed_50_listings.py",
            file=sys.stderr,
        )
        return 2

    return seed_via_db(dry_run=args.dry_run, seller_phone=args.seller_phone)


if __name__ == "__main__":
    raise SystemExit(main())
