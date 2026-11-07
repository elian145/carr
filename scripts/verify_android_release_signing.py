#!/usr/bin/env python3
"""Static verification of the Android release-signing safeguards (F-13).

Cheap, deterministic, stdlib-only: needs no Android SDK, Gradle or network.

Checks (non-zero exit + clear message on any violation):

  Gradle  (android/app/build.gradle.kts)
    * nothing references the debug signing config (``signingConfigs...debug``)
    * the ``release`` buildType only ever uses ``releaseConfig`` or no config
      (never debug) and honours the explicit ``unsignedReleaseRequested`` opt-in
    * a ``gradle.taskGraph.whenReady`` guard exists that inspects ``allTasks``
      for ANY task containing "release" (case-insensitive; not flavor-specific),
      throws ``GradleException`` and reads no bypass env var / property
    * no ``ALLOW_DEBUG_RELEASE_SIGNING``-style bypass anywhere

  CI      (codemagic.yaml, ios-codemagic.yaml, .github/workflows/*)
    * the legacy ``ALLOW_DEBUG_RELEASE_SIGNING`` bypass is absent everywhere
    * the unsigned opt-in ``CARNET_UNSIGNED_RELEASE`` appears ONLY in the
      ``android_release_unsigned`` Codemagic workflow, which must run this
      script and ``flutter analyze`` before building, assert the APK is really
      unsigned and publish it only under an ``UNSIGNED`` name
    * every other Android ``--release`` build must write ``signing.properties``

Usage:
  python scripts/verify_android_release_signing.py [--root DIR]
  python scripts/verify_android_release_signing.py --assert-unsigned-apk FILE.apk
"""
from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

GRADLE_FILE = "android/app/build.gradle.kts"
UNSIGNED_WORKFLOW = "android_release_unsigned"
UNSIGNED_OPT_IN = "CARNET_UNSIGNED_RELEASE"
LEGACY_BYPASS = "ALLOW_DEBUG_RELEASE_SIGNING"
SELF_NAME = "verify_android_release_signing.py"

# Env var / Gradle property names that smell like a signing bypass.
BYPASS_NAME_RE = re.compile(
    r"(?i)(ALLOW|BYPASS|DEBUG|SKIP|FORCE)[A-Z_]*SIGN|SIGN[A-Z_]*(ALLOW|BYPASS|DEBUG|SKIP|FORCE)"
)


# --------------------------------------------------------------------------
# Small Kotlin/YAML text helpers
# --------------------------------------------------------------------------
def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    except UnicodeDecodeError:
        return ""  # unreadable/non-UTF-8 file: every content check below then fails loudly



def strip_kotlin_comments(src: str) -> str:
    """Remove // and /* */ comments, leaving string literals intact."""
    out: list[str] = []
    i, n = 0, len(src)
    in_str = False
    while i < n:
        c = src[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(src[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
        elif src.startswith("//", i):
            while i < n and src[i] != "\n":
                i += 1
            continue
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j == -1 else j + 2
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def find_block(code: str, header_re: str, start: int = 0) -> tuple[str, int] | None:
    """Return (inner text, end index) of the first ``header { ... }`` block."""
    m = re.compile(header_re).search(code, start)
    if not m:
        return None
    i = code.find("{", m.end() - 1 if code[m.end() - 1] == "{" else m.end())
    if i == -1:
        return None
    depth, j, in_str = 0, i, False
    while j < len(code):
        c = code[j]
        if in_str:
            if c == "\\":
                j += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return code[i + 1 : j], j
        j += 1
    return None


# --------------------------------------------------------------------------
# Gradle checks
# --------------------------------------------------------------------------
def check_gradle(text: str) -> list[str]:
    errs: list[str] = []
    code = strip_kotlin_comments(text.replace("\r\n", "\n"))

    # 1. No reference to the debug signing config anywhere.
    for line in code.split("\n"):
        if re.search(r"signingConfigs?\b[^\n]*debug", line, re.I):
            errs.append(
                f"{GRADLE_FILE}: references the debug signing config "
                f"({line.strip()[:80]!r}); release builds must never use the debug key"
            )

    # 2. release buildType.
    bt = find_block(code, r"\bbuildTypes\s*\{")
    release = (
        find_block(bt[0], r"(?:\brelease|getByName\(\s*\"release\"\s*\))\s*\{")
        if bt
        else None
    )
    if release is None:
        errs.append(f"{GRADLE_FILE}: cannot find buildTypes {{ release {{ ... }} }}")
    else:
        body = release[0]
        if not re.search(r"\bsigningConfig\s*=", body):
            errs.append(f"{GRADLE_FILE}: release buildType does not set signingConfig explicitly")
        if re.search(r"debug", body, re.I):
            errs.append(f"{GRADLE_FILE}: release buildType mentions 'debug' (debug-signing fallback?)")
        names = set(re.findall(r"getByName\(\s*\"([^\"]+)\"\s*\)", body))
        if names - {"releaseConfig"}:
            errs.append(
                f"{GRADLE_FILE}: release buildType uses signing config(s) "
                f"{sorted(names - {'releaseConfig'})}; only 'releaseConfig' is allowed"
            )
        if "releaseConfig" not in body:
            errs.append(f"{GRADLE_FILE}: release buildType never selects 'releaseConfig'")
        if "unsignedReleaseRequested" not in body:
            errs.append(f"{GRADLE_FILE}: release buildType ignores the explicit unsigned opt-in")
        if not re.search(r"\belse\s*\{\s*null\s*\}", body):
            errs.append(
                f"{GRADLE_FILE}: release signingConfig fallback must be `null` (unsigned), "
                "not another signing config"
            )

    # 3. Task-graph guard covering every release task.
    guard = find_block(code, r"\bgradle\.taskGraph\.whenReady\s*\{")
    if guard is None:
        errs.append(f"{GRADLE_FILE}: missing gradle.taskGraph.whenReady release-signing guard")
    else:
        g = guard[0]
        if "allTasks" not in g:
            errs.append(f"{GRADLE_FILE}: guard does not inspect the task graph (allTasks)")
        if not re.search(r"contains\(\s*\"release\"\s*,\s*ignoreCase\s*=\s*true\s*\)", g):
            errs.append(
                f"{GRADLE_FILE}: guard must match every release task via "
                "name.contains(\"release\", ignoreCase = true)"
            )
        if re.search(r"(?i)\"[^\"]*(prod|dev|stage)[^\"]*\"", g):
            errs.append(f"{GRADLE_FILE}: guard is flavor-specific; it must cover all flavors")
        if "throw GradleException" not in g:
            errs.append(f"{GRADLE_FILE}: guard does not throw GradleException")
        if not re.search(r"hasCompleteSigningProps|loadSigningProperties", g):
            errs.append(f"{GRADLE_FILE}: guard does not check the signing properties")
        if re.search(r"getenv|findProperty|getProperty\(\s*\"(?!STORE_|KEY_)", g):
            errs.append(f"{GRADLE_FILE}: guard reads an env var/property (possible bypass)")
        allowed = {"unsignedReleaseRequested"}
        flags = set(re.findall(r"!\s*(\w*(?:[Uu]nsigned|[Aa]llow|[Bb]ypass|[Ss]kip)\w*)", g))
        if flags - allowed:
            errs.append(f"{GRADLE_FILE}: guard has unexpected bypass condition(s) {sorted(flags - allowed)}")
        if re.search(r"\bif\s*\(\s*false\b|\b&&\s*false\b", g):
            errs.append(f"{GRADLE_FILE}: guard contains a dead (always-false) condition")

    # 4. No bypass env var / property anywhere in the build script.
    if LEGACY_BYPASS in text:
        errs.append(f"{GRADLE_FILE}: legacy bypass {LEGACY_BYPASS} still referenced")
    for name in re.findall(r"(?:getenv|findProperty)\(\s*\"([^\"]+)\"", code):
        if BYPASS_NAME_RE.search(name):
            errs.append(f"{GRADLE_FILE}: reads suspicious signing bypass switch {name!r}")
    return errs


# --------------------------------------------------------------------------
# CI checks
# --------------------------------------------------------------------------
def split_codemagic_workflows(text: str) -> dict[str, str]:
    text = text.replace("\r\n", "\n")
    lines = text.split("\n")
    start = next((i for i, ln in enumerate(lines) if re.match(r"^workflows:\s*$", ln)), None)
    if start is None:
        return {}
    blocks: dict[str, list[str]] = {}
    current: str | None = None
    for ln in lines[start + 1 :]:
        if ln.strip() and not ln.startswith(" ") and not ln.startswith("#"):
            break  # next top-level key
        m = re.match(r"^  ([A-Za-z0-9_-]+):\s*(?:#.*)?$", ln)
        if m:
            current = m.group(1)
            blocks[current] = []
        elif current is not None:
            blocks[current].append(ln)
    return {k: "\n".join(v) for k, v in blocks.items()}


_BUILD_RE = re.compile(r"flutter\s+build\s+(apk|appbundle)\b[^\n]*")


def _commands(block: str) -> str:
    return re.sub(r"\\\n\s*", " ", block)  # join shell line continuations


def _android_release_builds(block: str) -> list[str]:
    return [m.group(0) for m in _BUILD_RE.finditer(_commands(block)) if "--release" in m.group(0)]


def check_codemagic(text: str) -> list[str]:
    errs: list[str] = []
    workflows = split_codemagic_workflows(text)
    if not workflows:
        return ["codemagic.yaml: no workflows found (parse error?)"]
    for name, block in workflows.items():
        uses_opt_in = UNSIGNED_OPT_IN in block
        if uses_opt_in and name != UNSIGNED_WORKFLOW:
            errs.append(
                f"codemagic.yaml[{name}]: {UNSIGNED_OPT_IN} is only allowed in the "
                f"{UNSIGNED_WORKFLOW} workflow"
            )
        builds = _android_release_builds(block)
        if name == UNSIGNED_WORKFLOW:
            continue
        if builds and "signing.properties" not in block:
            errs.append(
                f"codemagic.yaml[{name}]: Android release build without writing "
                "signing.properties (would fail the Gradle guard or ship unsigned)"
            )

    block = workflows.get(UNSIGNED_WORKFLOW)
    if block is not None:
        cmds = _commands(block)
        if not re.search(rf"^\s*{UNSIGNED_OPT_IN}:\s*\"?true\"?\s*$", block, re.M):
            errs.append(
                f"codemagic.yaml[{UNSIGNED_WORKFLOW}]: must set {UNSIGNED_OPT_IN}: \"true\" "
                "(explicit unsigned opt-in) in environment.vars"
            )
        first_build = cmds.find("flutter build")
        for what, pat in (
            ("verify_android_release_signing.py", r"python3?\s+scripts/verify_android_release_signing\.py(?!\S)"),
            ("flutter analyze", r"flutter\s+analyze\b"),
        ):
            m = re.search(pat, cmds)
            if not m:
                errs.append(f"codemagic.yaml[{UNSIGNED_WORKFLOW}]: must run {what} before building")
            elif first_build != -1 and m.start() > first_build:
                errs.append(f"codemagic.yaml[{UNSIGNED_WORKFLOW}]: {what} must run BEFORE flutter build")
        if "--assert-unsigned-apk" not in cmds:
            errs.append(
                f"codemagic.yaml[{UNSIGNED_WORKFLOW}]: must assert the APK is unsigned "
                "(--assert-unsigned-apk)"
            )
        if re.search(r"flutter\s+build\s+appbundle", cmds):
            errs.append(f"codemagic.yaml[{UNSIGNED_WORKFLOW}]: must not build an app bundle")
        m = re.search(r"^\s*artifacts:\s*\n((?:\s+-\s+.*\n?)+)", block + "\n", re.M)
        arts = re.findall(r"-\s+(\S+)", m.group(1)) if m else []
        if not arts:
            errs.append(f"codemagic.yaml[{UNSIGNED_WORKFLOW}]: no artifacts listed")
        for a in arts:
            if "UNSIGNED" not in a:
                errs.append(
                    f"codemagic.yaml[{UNSIGNED_WORKFLOW}]: artifact {a!r} must be named "
                    "unmistakably UNSIGNED"
                )
    return errs


def check_bypass_everywhere(root: Path) -> list[str]:
    errs: list[str] = []
    files: list[Path] = []
    for rel in ("codemagic.yaml", "ios-codemagic.yaml"):
        files.append(root / rel)
    files += sorted((root / ".github" / "workflows").glob("*.y*ml"))
    android = root / "android"
    if android.is_dir():
        for pat in ("*.kts", "*.gradle", "gradle.properties"):
            files += [p for p in android.rglob(pat) if "/build/" not in p.as_posix()]
    for f in files:
        if not f.is_file():
            continue
        t = _read(f)
        if LEGACY_BYPASS in t:
            errs.append(f"{f.relative_to(root).as_posix()}: contains the removed {LEGACY_BYPASS} bypass")
        if f.parent.name == "workflows" and f.suffix in (".yml", ".yaml"):
            if _android_release_builds(t) and "signing.properties" not in t:
                errs.append(
                    f"{f.relative_to(root).as_posix()}: Android --release build without signing.properties"
                )
        if UNSIGNED_OPT_IN in t and f.name not in ("codemagic.yaml", "build.gradle.kts"):
            errs.append(f"{f.relative_to(root).as_posix()}: {UNSIGNED_OPT_IN} not allowed here")
    return errs


def verify(root: Path) -> list[str]:
    errs: list[str] = []
    gradle = root / GRADLE_FILE
    if not gradle.is_file():
        errs.append(f"{GRADLE_FILE}: file not found under {root}")
    else:
        errs += check_gradle(_read(gradle))
    cm = root / "codemagic.yaml"
    if not cm.is_file():
        errs.append("codemagic.yaml: file not found")
    else:
        errs += check_codemagic(_read(cm))
    errs += check_bypass_everywhere(root)
    return errs


# --------------------------------------------------------------------------
# Unsigned APK assertion (used by the unsigned CI workflow)
# --------------------------------------------------------------------------
def assert_unsigned_apk(path: Path) -> list[str]:
    if not path.is_file():
        return [f"{path}: APK not found"]
    try:
        with zipfile.ZipFile(path) as z:
            sig_entries = [
                n for n in z.namelist() if re.match(r"(?i)^META-INF/[^/]+\.(RSA|DSA|EC|SF)$", n)
            ]
    except zipfile.BadZipFile:
        return [f"{path}: not a valid APK/zip"]
    errs = []
    if sig_entries:
        errs.append(f"{path.name}: contains v1 signature entries {sig_entries} - not unsigned")
    if b"APK Sig Block 42" in path.read_bytes():
        errs.append(f"{path.name}: contains an APK Signing Block (v2+) - not unsigned")
    return errs


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", type=Path, default=REPO_ROOT, help="repo root (default: this repo)")
    ap.add_argument("--assert-unsigned-apk", type=Path, metavar="APK", help="assert APK carries no signature")
    args = ap.parse_args(argv)

    if args.assert_unsigned_apk:
        errs = assert_unsigned_apk(args.assert_unsigned_apk)
        if errs:
            print("F-13 UNSIGNED-APK CHECK FAILED:", file=sys.stderr)
            for e in errs:
                print(f"  - {e}", file=sys.stderr)
            return 1
        print(f"OK: {args.assert_unsigned_apk.name} is unsigned (no signature present).")
        return 0

    errs = verify(args.root.resolve())
    if errs:
        print("F-13 ANDROID RELEASE-SIGNING VERIFICATION FAILED:", file=sys.stderr)
        for e in errs:
            print(f"  - {e}", file=sys.stderr)
        print(
            "Fix: release builds must fail without real signing (never fall back to the debug key); "
            "see android/app/build.gradle.kts and codemagic.yaml.",
            file=sys.stderr,
        )
        return 1
    print("OK: Android release-signing safeguards verified (no debug fallback, guard covers all release tasks, no CI bypass).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
