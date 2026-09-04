#!/usr/bin/env python3
"""
Standalone Cloudflare R2 (S3-compatible) operations.

Run in a subprocess so the parent process (eventlet/gunicorn) never creates a
boto3 SSL context — avoids RecursionError from eventlet monkey-patching ssl.

Stdin JSON:
  op: "put_object" | "presign_put" | "presign_get"
  account_id, bucket, access_key, secret_key, region (optional, default auto)
  key, content_type
  put_object: body_path (path to local file)
  presign_put: expires_in (optional), content_length (optional)
  presign_get: expires_in (optional) — C-10 private chat-media downloads

Stdout: {"ok": true, ...} or {"error": "..."}
"""
from __future__ import annotations

import json
import sys


def main() -> None:
    try:
        inp = json.load(sys.stdin)
    except Exception as e:
        json.dump({"error": f"invalid stdin json: {e}"}, sys.stdout)
        sys.exit(1)

    op = (inp.get("op") or "").strip()
    account_id = (inp.get("account_id") or "").strip()
    bucket = (inp.get("bucket") or "").strip()
    access_key = (inp.get("access_key") or "").strip()
    secret_key = (inp.get("secret_key") or "").strip()
    region = (inp.get("region") or "auto").strip() or "auto"
    key = (inp.get("key") or "").strip()
    content_type = (inp.get("content_type") or "application/octet-stream").strip()

    if not (account_id and bucket and access_key and secret_key and key and op):
        json.dump({"error": "missing required fields"}, sys.stdout)
        sys.exit(1)

    try:
        import boto3
        from botocore.config import Config

        endpoint = f"https://{account_id}.r2.cloudflarestorage.com"
        client = boto3.client(
            "s3",
            region_name=region,
            endpoint_url=endpoint,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            config=Config(signature_version="s3v4"),
        )

        if op == "put_object":
            body_path = (inp.get("body_path") or "").strip()
            if not body_path:
                json.dump({"error": "missing body_path"}, sys.stdout)
                sys.exit(1)
            with open(body_path, "rb") as fp:
                body = fp.read()
            client.put_object(
                Bucket=bucket,
                Key=key,
                Body=body,
                ContentType=content_type,
            )
            json.dump({"ok": True, "key": key, "bytes": len(body)}, sys.stdout)
            return

        if op == "presign_put":
            expires_in = int(inp.get("expires_in") or 900)
            put_params = {
                "Bucket": bucket,
                "Key": key,
                "ContentType": content_type,
            }
            raw_len = inp.get("content_length")
            if raw_len is not None:
                put_params["ContentLength"] = int(raw_len)
            url = client.generate_presigned_url(
                "put_object",
                Params=put_params,
                ExpiresIn=expires_in,
            )
            json.dump({"ok": True, "upload_url": url, "key": key}, sys.stdout)
            return

        if op == "presign_get":
            expires_in = int(inp.get("expires_in") or 600)
            url = client.generate_presigned_url(
                "get_object",
                Params={"Bucket": bucket, "Key": key},
                ExpiresIn=expires_in,
            )
            json.dump({"ok": True, "download_url": url, "key": key}, sys.stdout)
            return

        json.dump({"error": f"unknown op: {op}"}, sys.stdout)
        sys.exit(1)
    except Exception as e:
        json.dump({"error": str(e)}, sys.stdout)
        sys.exit(1)


if __name__ == "__main__":
    main()
