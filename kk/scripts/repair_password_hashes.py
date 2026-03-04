import argparse
from typing import Optional


def _invalid_hash(h: Optional[str]) -> bool:
    if h is None:
        return True
    hs = str(h).strip()
    # Historical placeholders seen in this repo
    if hs in ("", "x", "X", "placeholder"):
        return True
    # bcrypt hashes are typically much longer than 20 chars
    return len(hs) < 20


def main() -> int:
    """
    Repair legacy user password storage:
    - If password_hash is missing/invalid and plaintext password exists, re-hash it.
    - Always clear plaintext password column when present.
    - If password_hash is missing/invalid and plaintext is missing, deactivate the user (requires reset).
    """
    p = argparse.ArgumentParser()
    p.add_argument("--dry-run", action="store_true", help="Compute changes but do not commit.")
    args = p.parse_args()

    # Import inside main so env vars like DB_PATH/APP_ENV are read at runtime.
    from kk import app_new as app_module  # type: ignore
    from kk.models import db, User  # type: ignore

    app = app_module.app

    repaired_from_plaintext = 0
    cleared_plaintext = 0
    deactivated = 0

    with app.app_context():
        db.create_all()
        users = User.query.all()
        for u in users:
            legacy_plain = (getattr(u, "password", None) or "").strip()
            has_plain = bool(legacy_plain)
            if _invalid_hash(getattr(u, "password_hash", None)):
                if has_plain:
                    u.set_password(legacy_plain)
                    repaired_from_plaintext += 1
                else:
                    # No way to authenticate this user safely without a reset.
                    try:
                        u.is_active = False
                    except Exception:
                        pass
                    deactivated += 1

            if has_plain:
                try:
                    u.password = None
                    cleared_plaintext += 1
                except Exception:
                    pass

        if args.dry_run:
            db.session.rollback()
        else:
            db.session.commit()

    print(
        "REPAIR_PASSWORD_HASHES_OK "
        f"repaired_from_plaintext={repaired_from_plaintext} "
        f"cleared_plaintext={cleared_plaintext} "
        f"deactivated={deactivated} "
        f"dry_run={bool(args.dry_run)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

