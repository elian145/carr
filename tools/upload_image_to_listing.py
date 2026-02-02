import argparse
import json
import mimetypes
from pathlib import Path
import sys

import requests


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--base", required=True, help="API base like http://192.168.1.10:5003")
    p.add_argument("--email", required=True)
    p.add_argument("--password", required=True)
    p.add_argument("--listing", type=int, required=True)
    p.add_argument("--file", required=True, help="Path to image")
    args = p.parse_args()

    base = args.base.rstrip("/")
    login_url = f"{base}/api/auth/login"
    up_url = f"{base}/api/cars/{args.listing}/images"

    # Login
    r = requests.post(login_url, json={"username": args.email, "password": args.password}, timeout=30)
    if r.status_code >= 300:
        print(f"LOGIN_FAILED {r.status_code} {r.text[:300]}", file=sys.stderr)
        sys.exit(1)
    try:
        token = r.json().get("token")
    except Exception:
        token = None
    if not token:
        print("LOGIN_NO_TOKEN", file=sys.stderr)
        sys.exit(1)

    # Upload
    img_path = Path(args.file)
    if not img_path.is_file():
        print(f"FILE_NOT_FOUND {img_path}", file=sys.stderr)
        sys.exit(1)
    ctype, _ = mimetypes.guess_type(str(img_path))
    if not ctype:
        ctype = "image/jpeg"
    with img_path.open("rb") as fh:
        # Provide multiple field names for compatibility
        files = [
            ("image", (img_path.name, fh, ctype)),
        ]
        headers = {"Authorization": f"Bearer {token}"}
        ur = requests.post(up_url, headers=headers, files=files, timeout=120)
    print(ur.status_code)
    print(ur.text)


if __name__ == "__main__":
    main()

