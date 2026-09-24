#!/usr/bin/env python3
"""
Standalone Cloudflare R2 (S3-compatible) operations.

Run in a subprocess so the parent process (eventlet/gunicorn) never creates a
boto3 SSL context — avoids RecursionError from eventlet monkey-patching ssl.

Stdin JSON:
  op: "put_object" | "get_object" | "presign_put" | "presign_get" |
      "delete_object" | "list_and_delete_stale"
  account_id, bucket, access_key, secret_key, region (optional, default auto)
  key, content_type
  put_object: body_path (path to local file) -- uploaded via boto3's
    managed `upload_file()` transfer, which streams straight from disk
    (never buffered as a single in-memory `bytes` object in this
    subprocess, regardless of file size)
  get_object: dest_path (local path to download into) -- OOM-fix follow-up:
    lets a Celery worker on a *different* Render service/disk than the web
    process that enqueued the job fetch the original upload bytes, since
    Render never shares a local disk across services.
  presign_put: expires_in (optional), content_length (optional)
  presign_get: expires_in (optional) — C-10 private chat-media downloads
  delete_object: none (S3's DeleteObject is idempotent -- deleting an
    already-missing key is not an error)
  list_and_delete_stale: prefix, older_than_seconds -- deletes every object
    under ``prefix`` whose LastModified is older than ``older_than_seconds``
    ago. Used to sweep abandoned R2 staging objects (see
    kk/tasks/image_tasks.py::cleanup_stale_image_staging_objects) if a Celery
    job was lost/never ran to completion.

Stdout: {"ok": true, ...} or {"error": "..."}
"""
from __future__ import annotations

import json
import os
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

    # list_and_delete_stale operates on a prefix, not a single object key.
    key_required = op != "list_and_delete_stale"
    if not (account_id and bucket and access_key and secret_key and op) or (
        key_required and not key
    ):
        json.dump({"error": "missing required fields"}, sys.stdout)
        sys.exit(1)

    try:
        import boto3
        from boto3.s3.transfer import TransferConfig
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

        # OOM-fix follow-up (memory-safety bound on top of the streaming
        # upload_file() fix): boto3's default TransferConfig allows up to
        # 10 concurrent part-upload threads, each holding one multipart
        # chunk in memory at a time -- for the default 8 MiB chunk size,
        # that is up to ~80 MiB of concurrent in-flight chunk buffers for
        # a single large upload, on top of whatever else this container is
        # doing. max_concurrency=2 bounds that to ~2 chunks in flight
        # (~16 MiB) regardless of file size, while multipart uploads stay
        # enabled (multipart_threshold is boto3's default -- unchanged) so
        # large video files are still uploaded in parts, not as one
        # oversized single-part PUT.
        _UPLOAD_TRANSFER_CONFIG = TransferConfig(
            multipart_chunksize=8 * 1024 * 1024,  # ~8 MiB
            max_concurrency=2,
        )

        if op == "put_object":
            body_path = (inp.get("body_path") or "").strip()
            if not body_path:
                json.dump({"error": "missing body_path"}, sys.stdout)
                sys.exit(1)
            size = os.path.getsize(body_path)
            # OOM-fix follow-up: boto3's managed file upload
            # (`upload_file`) streams the body straight from disk using
            # S3's TransferManager -- a single-part streamed PUT for small
            # files, automatic multipart upload (fixed-size ~8 MiB chunks,
            # at most 2 concurrent -- see `_UPLOAD_TRANSFER_CONFIG` above)
            # for large ones. Unlike the previous
            # `open(body_path, "rb").read()` + `put_object(Body=<bytes>)`
            # implementation, this subprocess never holds the full file as
            # one in-memory `bytes` object, regardless of file size --
            # this is what makes both `r2_put_file()` (large video
            # uploads, R2 async-image-staging uploads) and
            # `r2_put_bytes()` (which stages its bytes to a temp file
            # before reaching this same op) genuinely disk-streamed at the
            # container level, not just "streamed into this process, then
            # buffered here".
            client.upload_file(
                body_path,
                bucket,
                key,
                ExtraArgs={"ContentType": content_type},
                Config=_UPLOAD_TRANSFER_CONFIG,
            )
            json.dump({"ok": True, "key": key, "bytes": size}, sys.stdout)
            return

        if op == "get_object":
            dest_path = (inp.get("dest_path") or "").strip()
            if not dest_path:
                json.dump({"error": "missing dest_path"}, sys.stdout)
                sys.exit(1)
            # download_file streams the body straight to disk in chunks
            # (no full-object bytes held in this subprocess's memory).
            client.download_file(bucket, key, dest_path)
            size = os.path.getsize(dest_path)
            json.dump({"ok": True, "key": key, "bytes": size}, sys.stdout)
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

        if op == "delete_object":
            # S3's DeleteObject is idempotent: deleting a key that does not
            # exist still returns 204/success rather than raising, so a
            # media row whose storage object was already removed (or never
            # made it to R2) deletes cleanly here too.
            client.delete_object(Bucket=bucket, Key=key)
            json.dump({"ok": True, "key": key}, sys.stdout)
            return

        if op == "list_and_delete_stale":
            import datetime

            prefix = (inp.get("prefix") or "").strip()
            if not prefix:
                json.dump({"error": "missing prefix"}, sys.stdout)
                sys.exit(1)
            older_than_seconds = int(inp.get("older_than_seconds") or 0)
            cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(
                seconds=older_than_seconds
            )
            deleted = 0
            paginator = client.get_paginator("list_objects_v2")
            for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
                stale_keys = [
                    {"Key": obj["Key"]}
                    for obj in page.get("Contents", [])
                    if obj.get("LastModified") and obj["LastModified"] < cutoff
                ]
                for i in range(0, len(stale_keys), 1000):
                    batch = stale_keys[i : i + 1000]
                    if batch:
                        client.delete_objects(Bucket=bucket, Delete={"Objects": batch})
                        deleted += len(batch)
            json.dump({"ok": True, "deleted": deleted}, sys.stdout)
            return

        json.dump({"error": f"unknown op: {op}"}, sys.stdout)
        sys.exit(1)
    except Exception as e:
        json.dump({"error": str(e)}, sys.stdout)
        sys.exit(1)


if __name__ == "__main__":
    main()
