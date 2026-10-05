"""Byte portability of the evidence tooling (the same commit must validate identically on Windows with core.autocrlf
true/false, Linux, macOS, CI clones and `git archive`).

Two kinds of files are hashed / compared byte-for-byte, and each has ONE pinned byte form:

* preserved source snapshots (evidence/**/_source_text/*.txt, reports/quote_repair_snapshots/**/*.txt): `-text` in
  .gitattributes, so Git never converts them; the committed blob bytes are the bytes hashed into integrity.content_sha256.
* generated / authored JSON: written by enrichment_lib.write_json with explicit CRLF and pinned to `text eol=crlf`.

The git-based checks are skipped when git (or a work tree) is not available; everything else always runs."""
import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import enrichment_lib as L  # noqa: E402
import fetch_snapshot as F  # noqa: E402

SNAPSHOT_RULES = ("evidence/**/_source_text/*.txt", "reports/quote_repair_snapshots/**/*.txt")
JSON_DIRS = ("evidence", "generated", "reports", "proposals")


def snapshot_files():
    out = []
    for p in sorted((HERE / "evidence").rglob("*.txt")):
        if p.parent.name == "_source_text":
            out.append(p)
    out += sorted((HERE / "reports" / "quote_repair_snapshots").rglob("*.txt"))
    return out


def json_files():
    return [p for d in JSON_DIRS for p in sorted((HERE / d).rglob("*.json"))]


def rel(p: Path) -> str:
    return p.relative_to(HERE).as_posix()


def _regex(pattern: str):
    """Minimal gitattributes glob -> regex (patterns containing '/' are anchored at the .gitattributes directory)."""
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif pattern[i] == "*":
            out += "[^/]*"
            i += 1
        else:
            out += re.escape(pattern[i])
            i += 1
    return re.compile("^" + out + "$")


def attribute_rules():
    rules = []
    for line in (HERE / ".gitattributes").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        pat, *attrs = line.split()
        rules.append((_regex(pat), attrs))
    return rules


def attrs_for(path: str, rules):
    got = {}
    for rx, attrs in rules:  # later lines win, as in Git
        if rx.match(path):
            for a in attrs:
                if a.startswith("-"):
                    got[a[1:]] = False
                elif "=" in a:
                    k, v = a.split("=", 1)
                    got[k] = v
                else:
                    got[a] = True
    return got


def git(*args, input=None):
    return subprocess.run(["git", "-C", str(HERE), *args], capture_output=True, input=input)


def have_git_worktree() -> bool:
    if not shutil.which("git"):
        return False
    r = git("rev-parse", "--is-inside-work-tree")
    return r.returncode == 0 and r.stdout.strip() == b"true"


def evidence_snapshot_hashes():
    """{snapshot path relative to tools/catalog_enrichment: recorded content_sha256} for every evidence file."""
    out = {}
    for ev in list((HERE / "evidence").glob("*.json")) + list((HERE / "evidence").glob("*/*.json")):
        for sid, s in (L.read_json(ev).get("sources") or {}).items():
            integ = s.get("integrity") or {}
            if integ.get("snapshot_path") and integ.get("content_sha256"):
                out[integ["snapshot_path"]] = integ["content_sha256"]
    return out


class AttributeCoverage(unittest.TestCase):
    def test_every_snapshot_is_covered_by_a_minus_text_rule(self):
        rules = attribute_rules()
        files = snapshot_files()
        self.assertGreater(len(files), 40)
        for p in files:
            a = attrs_for(rel(p), rules)
            self.assertIs(a.get("text"), False, f"{rel(p)}: not '-text' in tools/catalog_enrichment/.gitattributes")

    def test_every_hashed_or_compared_json_is_pinned_to_crlf(self):
        rules = attribute_rules()
        files = json_files()
        self.assertGreater(len(files), 40)
        for p in files:
            a = attrs_for(rel(p), rules)
            self.assertEqual((a.get("text"), a.get("eol")), (True, "crlf"), rel(p))

    def test_effective_attributes_according_to_git(self):
        if not have_git_worktree():
            self.skipTest("git work tree not available")
        paths = [rel(p) for p in snapshot_files() + json_files()]
        r = git("check-attr", "--stdin", "-z", "text", "eol", input=("\0".join(paths) + "\0").encode())
        self.assertEqual(r.returncode, 0, r.stderr)
        fields = r.stdout.decode().split("\0")
        eff = {}
        for i in range(0, len(fields) - 2, 3):
            eff.setdefault(fields[i], {})[fields[i + 1]] = fields[i + 2]
        for p in snapshot_files():
            self.assertEqual(eff[rel(p)]["text"], "unset", rel(p))
        for p in json_files():
            self.assertEqual((eff[rel(p)]["text"], eff[rel(p)]["eol"]), ("set", "crlf"), rel(p))


class SnapshotHashes(unittest.TestCase):
    def test_every_recorded_hash_matches_the_snapshot_bytes_on_disk(self):
        rec = evidence_snapshot_hashes()
        self.assertGreater(len(rec), 60)
        for path, sha in rec.items():
            raw = (HERE / path).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), sha, path)

    def test_a_snapshot_never_mixes_line_endings(self):
        for p in snapshot_files():
            raw = p.read_bytes()
            crlf, lf = raw.count(b"\r\n"), raw.count(b"\n")
            self.assertIn(crlf, (0, lf), f"{rel(p)} mixes CRLF and bare LF")

    def test_new_snapshots_are_written_in_one_canonical_form(self):
        """fetch_snapshot.snapshot_bytes is what new research hashes AND writes (write_bytes): LF, one trailing newline."""
        self.assertEqual(F.snapshot_bytes("a\nb\n\n\n"), b"a\nb\n")
        self.assertNotIn(b"\r", F.snapshot_bytes("line one\nline two"))
        # the file is written from exactly those bytes (bytes mode, so no platform newline translation) ...
        src = (HERE / "fetch_snapshot.py").read_text(encoding="utf-8")
        self.assertIn('.write_bytes(snap)', src)
        self.assertNotRegex(src, r"_source_text[^\n]*\.write_text\(")
        # ... and revalidation (test_revalidation.py) proves sha256(file bytes) == the recorded content_sha256.

    def test_committed_blobs_equal_the_working_tree_snapshot_bytes(self):
        """What a fresh clone / git archive will contain (the index blob) must hash to the recorded sha256."""
        if not have_git_worktree():
            self.skipTest("git work tree not available")
        r = git("ls-files", "-s", "-z", "--", "evidence", "reports/quote_repair_snapshots")
        entries = [e for e in r.stdout.decode().split("\0") if e]
        blobs = {}
        for e in entries:
            meta, path = e.split("\t", 1)
            blobs[path] = meta.split()[1]
        snaps = {rel(p) for p in snapshot_files()}
        tracked = sorted(snaps & set(blobs))
        if not tracked:
            self.skipTest("snapshots are not tracked in this checkout")
        rec = evidence_snapshot_hashes()
        for path in tracked:
            blob = git("cat-file", "blob", blobs[path]).stdout
            disk = (HERE / path).read_bytes()
            self.assertEqual(blob, disk, f"{path}: Git blob differs from the working-tree bytes (stage the file; a clone would get different bytes)")
            if path in rec:
                self.assertEqual(hashlib.sha256(blob).hexdigest(), rec[path], f"{path}: committed blob does not hash to the recorded sha256")


class JsonBytes(unittest.TestCase):
    def test_json_is_always_written_with_crlf_regardless_of_platform(self):
        data = {"a": [1, 2, {"b": "x\ny"}], "t": "\u00e9\u2014"}
        raw = L.json_bytes(data)
        self.assertTrue(raw.endswith(b"}\r\n"))
        self.assertEqual(raw.count(b"\n"), raw.count(b"\r\n"))  # no bare LF anywhere
        self.assertEqual(L.json.loads(raw.decode("utf-8")), data)  # the newline inside the string stayed an escaped \n
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "x.json"
            L.write_json(p, data)
            self.assertEqual(p.read_bytes(), raw)

    def test_committed_json_files_use_the_pinned_form(self):
        for p in json_files():
            raw = p.read_bytes()
            self.assertEqual(raw.count(b"\n"), raw.count(b"\r\n"), f"{rel(p)} has bare LF line endings (expected the pinned CRLF form)")


if __name__ == "__main__":
    unittest.main()
