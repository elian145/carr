"""Newline portability of the IQ Cars pipeline.

Every canonical artifact (raw/, generated/) is written with an explicit CRLF through canonical_io, never through the platform
newline of Path.write_text(). Committed artifacts carry sha256 relationships (build_overlay records the hash of the raw catalog
and the normalized dataset), so Windows and Linux regeneration must be byte-identical.
"""
import json
import re
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import canonical_io as C  # noqa: E402

PIPELINE = ("normalize.py", "compare_carnet.py", "build_overlay.py", "extract_iqcars.py")


def _text(p: Path) -> str:
    return p.read_text(encoding="utf-8")


class CanonicalIo(unittest.TestCase):
    def test_every_newline_form_becomes_crlf(self):
        for src in ("a\nb\n", "a\r\nb\r\n", "a\rb\r", "a\nb\r\nc\r"):
            out = C.canonical_bytes(src)
            self.assertNotIn(b"\r\r", out)
            self.assertEqual(out.count(b"\n"), out.count(b"\r\n"), src)  # no bare LF
            self.assertEqual(out.count(b"\r"), out.count(b"\r\n"), src)  # no bare CR

    def test_non_ascii_is_utf8_and_unchanged(self):
        self.assertEqual(C.canonical_bytes("ـ\u0644\u0627\n"), "ـ\u0644\u0627\r\n".encode("utf-8"))

    def test_write_is_byte_exact_independent_of_platform_newline(self):
        import os
        import tempfile

        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "x.json"
            C.write_text_canonical(p, '{"a": 1}\n')
            self.assertEqual(p.read_bytes(), b'{"a": 1}\r\n')
            self.assertEqual(os.path.getsize(p), 10)


class NoPlatformNewlineWriters(unittest.TestCase):
    def test_pipeline_modules_never_use_write_text(self):
        for name in PIPELINE + ("iqcars_client.py",):
            src = _text(HERE / name)
            self.assertIsNone(re.search(r"\.write_text\(", src), f"{name} must write through canonical_io")

    def test_appended_logs_use_explicit_newline(self):
        for name in ("extract_iqcars.py", "iqcars_client.py"):
            src = _text(HERE / name)
            for m in re.finditer(r'open\([^)]*"a"[^)]*\)', src):
                self.assertIn("newline=NEWLINE", m.group(0), name)


class CommittedArtifactsAreCanonical(unittest.TestCase):
    def _artifacts(self):
        files = [HERE / "raw" / "iqcars_catalog.json"]
        files += sorted((HERE / "raw" / "samples").glob("*.json"))
        files += sorted((HERE / "generated").rglob("*.json")) + sorted((HERE / "generated").rglob("*.md"))
        return files

    def test_artifacts_are_crlf_only(self):
        for p in self._artifacts():
            b = p.read_bytes()
            self.assertGreater(len(b), 0, p.name)
            self.assertEqual(b.count(b"\n"), b.count(b"\r\n"), f"{p.name}: bare LF")
            self.assertEqual(b.count(b"\r"), b.count(b"\r\n"), f"{p.name}: bare CR")
            self.assertTrue(b.endswith(b"\r\n"), p.name)

    def test_json_artifacts_round_trip_to_identical_bytes(self):
        for p in self._artifacts():
            if p.suffix != ".json":
                continue
            b = p.read_bytes()
            again = C.canonical_bytes(json.dumps(json.loads(b.decode("utf-8")), ensure_ascii=False, indent=1) + "\n")
            self.assertEqual(again, b, f"{p.name} is not in the canonical form")


if __name__ == "__main__":
    unittest.main()
