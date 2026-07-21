#!/usr/bin/env python3
"""
Capture CarNet store screenshots from Android emulator via UI Automator.

Prereqs: emulator-5554, com.carzo.app.dev installed, Pillow.

  python scripts/capture_store_screenshots.py
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "store_assets" / "screenshots"
ADB = Path.home() / "AppData/Local/Android/Sdk/platform-tools/adb.exe"
PACKAGE = "com.carzo.app.dev"
PREFS = "FlutterSharedPreferences.xml"
SIZE_6_7 = (1290, 2796)
SIZE_5_5 = (1242, 2208)

# Nav labels per locale (bottom bar)
NAV = {
    "en": {
        "home": ("Home",),
        "sell": ("Sell",),
        "dealers": ("Dealerships", "Dealers"),
        "profile": ("Profile",),
        "later": ("Later",),
        "search": ("Search",),
    },
    "ar": {
        "home": ("الرئيسية", "الصفحة الرئيسية", "Home"),
        "sell": ("بيع", "Sell"),
        "dealers": ("المعارض", "الوكلاء", "الوكالات", "Dealerships", "Dealers"),
        "profile": ("الملف الشخصي", "الملف", "الحساب", "Profile"),
        "later": ("لاحقاً", "لاحقا", "Later"),
        "search": ("بحث", "Search"),
    },
    "ku": {
        "home": ("ماڵەوە", "سەرەکی", "Home"),
        "sell": ("فرۆشتن", "Sell"),
        "dealers": ("نمایشگەکان", "ناوەندەکان", "فرۆشیارەکان", "Dealerships"),
        "profile": ("پرۆفایل", "پڕۆفایڵ", "Profile"),
        "later": ("دواتر", "Later"),
        "search": ("گەڕان", "Search"),
    },
}


def adb(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(ADB), "-s", "emulator-5554", *args],
        check=check,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
    )


def wait(s: float) -> None:
    time.sleep(s)


def force_stop() -> None:
    adb("shell", "am", "force-stop", PACKAGE, check=False)


def launch() -> None:
    adb(
        "shell",
        "am",
        "start",
        "-n",
        f"{PACKAGE}/com.carzo.app.MainActivity",
        check=False,
    )


def set_locale(code: str) -> None:
    force_stop()
    launch()
    wait(5)
    force_stop()
    wait(1)
    content = (
        "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n"
        "<map>\n"
        f'    <string name="flutter.app_locale">{code}</string>\n'
        "</map>\n"
    )
    host = OUT / "_raw" / f"prefs_{code}.xml"
    host.parent.mkdir(parents=True, exist_ok=True)
    host.write_text(content, encoding="utf-8")
    remote = f"/data/local/tmp/carnet_prefs_{code}.xml"
    adb("push", str(host), remote, check=False)
    adb("shell", f"run-as {PACKAGE} mkdir -p shared_prefs", check=False)
    adb(
        "shell",
        f"cat {remote} | run-as {PACKAGE} sh -c 'cat > shared_prefs/{PREFS}'",
        check=False,
    )
    adb("shell", f"rm {remote}", check=False)


def ui_dump() -> ET.Element:
    remote = "/sdcard/Download/carnet_ui.xml"
    adb("shell", "uiautomator", "dump", remote, check=False)
    wait(0.5)
    host = OUT / "_raw" / "ui.xml"
    host.parent.mkdir(parents=True, exist_ok=True)
    adb("pull", remote, str(host), check=False)
    return ET.parse(host).getroot()


def _node_text(n: ET.Element) -> str:
    return (n.attrib.get("text") or "") + " " + (n.attrib.get("content-desc") or "")


def find_bounds(root: ET.Element, labels: tuple[str, ...]) -> tuple[int, int] | None:
    for n in root.iter("node"):
        t = _node_text(n).strip()
        for label in labels:
            if label and label in t:
                m = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.attrib.get("bounds", ""))
                if not m:
                    continue
                x1, y1, x2, y2 = map(int, m.groups())
                return (x1 + x2) // 2, (y1 + y2) // 2
    return None


def tap_label(labels: tuple[str, ...], retries: int = 4) -> bool:
    for _ in range(retries):
        try:
            root = ui_dump()
        except Exception:
            wait(1)
            continue
        pt = find_bounds(root, labels)
        if pt:
            adb("shell", "input", "tap", str(pt[0]), str(pt[1]), check=False)
            wait(2.5)
            return True
        wait(1.2)
    return False


def ensure_in_app() -> None:
    root = ui_dump()
    xml = ET.tostring(root, encoding="unicode")
    if PACKAGE not in xml and "CarNet" not in xml and "carzo" not in xml.lower():
        launch()
        wait(8)


def screencap_raw(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    remote = "/sdcard/Download/carnet_screencap.png"
    last_err: Exception | None = None
    for attempt in range(4):
        try:
            adb("shell", "rm", "-f", remote, check=False)
            adb("shell", "screencap", "-p", remote, check=True)
            wait(0.4)
            adb("pull", remote, str(path), check=True)
            if path.is_file() and path.stat().st_size > 1000:
                return
        except Exception as e:
            last_err = e
            wait(1.5)
    raise RuntimeError(f"screencap failed for {path}: {last_err}")


def fit_cover(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    tw, th = size
    sw, sh = img.size
    scale = max(tw / sw, th / sh)
    nw, nh = int(sw * scale), int(sh * scale)
    resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
    left = (nw - tw) // 2
    top = (nh - th) // 2
    return resized.crop((left, top, left + tw, top + th))


def export_sizes(raw_path: Path, locale: str, name: str) -> None:
    img = Image.open(raw_path).convert("RGB")
    for label, size in (("phone_6_7", SIZE_6_7), ("phone_5_5", SIZE_5_5)):
        out = OUT / locale / label / f"{name}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        fit_cover(img, size).save(out, format="PNG", optimize=True)
        print(f"  wrote {out.relative_to(ROOT)} ({size[0]}x{size[1]})")


def capture_locale(locale: str, skip_locale_write: bool) -> None:
    print(f"\n=== locale={locale} ===")
    labels = NAV.get(locale, NAV["en"])
    if not skip_locale_write:
        set_locale(locale)
    force_stop()
    wait(1)
    launch()
    wait(16)
    ensure_in_app()

    # Dismiss dealer approval dialog if shown
    tap_label(labels["later"], retries=2)
    wait(2)
    ensure_in_app()

    raw_dir = OUT / "_raw" / locale
    raw_dir.mkdir(parents=True, exist_ok=True)

    tap_label(labels["home"])
    wait(8)
    raw = raw_dir / "01_home.png"
    screencap_raw(raw)
    export_sizes(raw, locale, "01_home")

    # Listing detail from a card (avoid call buttons)
    adb("shell", "input", "tap", "280", "1050", check=False)
    wait(5)
    tap_label(labels["later"], retries=1)
    raw = raw_dir / "02_listing_detail.png"
    screencap_raw(raw)
    export_sizes(raw, locale, "02_listing_detail")

    # Listing detail has no bottom nav — relaunch into home shell
    force_stop()
    wait(1)
    launch()
    wait(12)
    tap_label(labels["later"], retries=2)
    wait(2)
    tap_label(labels["home"])
    wait(3)

    tap_label(labels["dealers"])
    wait(5)
    raw = raw_dir / "03_dealers.png"
    screencap_raw(raw)
    export_sizes(raw, locale, "03_dealers")

    # Profile before Sell: Add Listing hides the bottom nav
    tap_label(labels["home"])
    wait(2)
    tap_label(labels["profile"])
    wait(5)
    raw = raw_dir / "05_profile.png"
    screencap_raw(raw)
    export_sizes(raw, locale, "05_profile")

    tap_label(labels["home"])
    wait(2)
    tap_label(labels["sell"])
    wait(5)
    raw = raw_dir / "04_sell.png"
    screencap_raw(raw)
    export_sizes(raw, locale, "04_sell")


def main() -> None:
    if not ADB.is_file():
        print(f"adb not found: {ADB}", file=sys.stderr)
        raise SystemExit(1)
    if "emulator-5554" not in adb("devices").stdout:
        print("emulator-5554 not ready", file=sys.stderr)
        raise SystemExit(1)

    parser = argparse.ArgumentParser()
    parser.add_argument("--locales", default="en,ar,ku")
    parser.add_argument("--skip-locale-write", action="store_true")
    args = parser.parse_args()
    for loc in [x.strip() for x in args.locales.split(",") if x.strip()]:
        try:
            capture_locale(loc, args.skip_locale_write)
        except Exception as e:
            print(f"ERROR capturing {loc}: {e}", file=sys.stderr)
            continue
    print("\nDone. Review store_assets/screenshots/ before store upload.")


if __name__ == "__main__":
    main()
