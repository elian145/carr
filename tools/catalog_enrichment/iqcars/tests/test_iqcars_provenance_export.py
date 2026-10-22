"""Runtime provenance asset (assets/car_iqcars_provenance.json) export guards.

The asset tells the app which CarNet brands / models / trims are IQ Cars entries so the pickers can list IQ Cars first. It
must be (a) exactly what the exporter derives from the reviewed reports, (b) limited to exact identities (no lookalike is
ever merged, no excluded/ambiguous/unmatched model is claimed), and (c) free of research metadata.
"""
import copy
import json
import re
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import export_runtime_provenance as P  # noqa: E402

MATCHING = json.loads(P.MATCHING.read_text(encoding="utf-8"))
OPTIONS = json.loads(P.OPTIONS.read_text(encoding="utf-8"))
EXC = json.loads(P.EXCLUSIONS.read_text(encoding="utf-8"))
CATALOG = json.loads(P.CATALOG.read_text(encoding="utf-8"))
OVERLAY = json.loads(P.OVERLAY.read_text(encoding="utf-8"))
ASSET = json.loads(P.OUT.read_text(encoding="utf-8"))
MODELS = {(b, m): v for b, ms in ASSET.items() if not b.startswith("_") for m, v in ms.items()}
OVERLAY_MODELS = {(b, m) for b, ms in OVERLAY.items() if not b.startswith("_") for m in ms}
CATALOG_MODELS = {(b, m) for b, ms in CATALOG["models"].items() for m in ms}


def _build():
    return P.build(MATCHING, OPTIONS, EXC, CATALOG, OVERLAY)


class AssetMatchesReports(unittest.TestCase):
    def test_asset_is_up_to_date(self):
        self.assertEqual(P.OUT.read_bytes().replace(b"\r\n", b"\n"), P.render(_build()))

    def test_deterministic(self):
        again = P.build(copy.deepcopy(MATCHING), copy.deepcopy(OPTIONS), copy.deepcopy(EXC), copy.deepcopy(CATALOG), copy.deepcopy(OVERLAY))
        self.assertEqual(P.render(_build()), P.render(again))

    def test_check_mode_passes(self):
        self.assertEqual(P.main(["--check"]), 0)

    def test_meta_counts_and_kind(self):
        meta = ASSET["_meta"]
        self.assertEqual(meta["kind"], "iqcars_provenance")
        self.assertEqual(meta["format"], P.FORMAT_VERSION)
        self.assertEqual(meta["models"], len(MODELS))
        self.assertEqual(meta["brands"], len({b for b, _ in MODELS}))
        self.assertEqual(meta["shared_trims"], sum(len(v.get("trims", [])) for v in MODELS.values()))
        self.assertEqual(meta["source_sha256"]["matching"], P._sha256(P.MATCHING))
        self.assertEqual(meta["source_sha256"]["catalog"], P._sha256(P.CATALOG))

    def test_compact(self):
        self.assertLess(P.OUT.stat().st_size, 60_000)


class Identities(unittest.TestCase):
    def test_every_identity_is_a_catalog_model_in_carnet_spelling(self):
        self.assertTrue(set(MODELS) <= CATALOG_MODELS)

    def test_every_overlay_model_has_an_identity(self):
        self.assertTrue(OVERLAY_MODELS <= set(MODELS))

    def test_blocked_models_are_never_claimed(self):
        blocked = set()
        for sec in ("ambiguous_iq_models", "unmatched_iq_models", "explicitly_excluded_models"):
            blocked |= {(e["iq_brand"], e["iq_model"]) for e in EXC[sec]}
        claimed_iq = {(x["iq_brand"], x["iq_model"]) for x in MATCHING["matched"] if (x["carnet_brand"], x["carnet_model"]) in MODELS}
        self.assertFalse(claimed_iq & blocked)
        # the ambiguous Land Cruiser FJ is not claimed through any CarNet identity either
        fj = [x for x in MATCHING["matched"] if x["iq_model"] == "Land Cruiser FJ"]
        for x in fj:
            self.assertNotIn((x["carnet_brand"], "Land Cruiser FJ"), MODELS)

    def test_land_cruiser_and_prado_are_distinct_identities(self):
        self.assertIn(("Toyota", "Land Cruiser"), MODELS)
        self.assertIn(("Toyota", "Land Cruiser Prado"), MODELS)
        self.assertIn(("Toyota", "Corolla"), MODELS)
        self.assertIn(("Toyota", "Corolla Cross"), MODELS)


class SharedTrims(unittest.TestCase):
    def test_shared_trims_are_carnet_trims_and_iq_trims(self):
        iq_by_id = {m["model_id"]: m for m in OPTIONS["models"]}
        iq_trims_by_carnet = {}
        for x in MATCHING["matched"]:
            iq_trims_by_carnet.setdefault((x["carnet_brand"], x["carnet_model"]), set()).update(iq_by_id[x["iq_model_id"]]["trims"])
        for key, v in MODELS.items():
            carnet = P._carnet_trims(CATALOG, *key)
            for t in v.get("trims", []):
                self.assertIn(t, carnet, key)
                self.assertIn(t, iq_trims_by_carnet[key], key)

    def test_shared_trims_exclude_the_other_placeholder(self):
        for key, v in MODELS.items():
            for t in v.get("trims", []):
                self.assertNotIn(t.casefold(), P.PLACEHOLDER_TRIMS, key)

    def test_approved_additions_are_never_also_shared(self):
        for (b, m) in OVERLAY_MODELS:
            adds = {t.casefold() for t in OVERLAY[b][m].get("trims_add", [])}
            shared = {t.casefold() for t in MODELS[(b, m)].get("trims", [])}
            self.assertFalse(adds & shared, (b, m))
            carnet = {t.casefold() for t in P._carnet_trims(CATALOG, b, m)}
            self.assertFalse(adds & carnet, (b, m))

    def test_lookalikes_are_not_merged(self):
        # Held IQ lookalikes (GX.R / VX.R / EX.R / VX.S) are different trims from CarNet's GXR / VXR / EXR / VXS.
        shared = set(MODELS[("Toyota", "Land Cruiser")].get("trims", []))
        self.assertEqual(shared, {"GX", "VX"})
        for lookalike in ("GXR", "VXR", "EXR", "VXS"):
            self.assertNotIn(lookalike, shared)
        # Corolla: IQ "Limited" is not CarNet's "Limited Special Edition"; CarNet "IM" is not IQ's "iM".
        corolla = set(MODELS[("Toyota", "Corolla")].get("trims", []))
        self.assertNotIn("Limited Special Edition", corolla)
        self.assertNotIn("IM", corolla)
        self.assertNotIn("Limited", corolla)

    def test_strict_name_equality_only(self):
        # Never fuzzy: a shared trim equals a CarNet trim after whitespace normalisation, nothing looser.
        for key, v in MODELS.items():
            carnet = P._carnet_trims(CATALOG, *key)
            for t in v.get("trims", []):
                self.assertEqual(t, P.norm_ws(t), key)
                self.assertIn(t, carnet, key)


class AssetContent(unittest.TestCase):
    def test_only_expected_keys(self):
        for key, v in MODELS.items():
            self.assertLessEqual(set(v), {"trims"}, key)

    def test_no_research_metadata(self):
        text = P.OUT.read_text(encoding="utf-8").lower()
        text = re.sub(r'"semantics":"[^"]*"', "", text)
        text = re.sub(r'"source_sha256":\{[^}]*\}', "", text)
        for banned in ("http", "iq_", "evidence", "raw_values", "held", "warning", "relationship"):
            self.assertNotIn(banned, text, banned)

    def test_render_is_lf_utf8_one_line_per_brand(self):
        data = P.render(_build())
        self.assertNotIn(b"\r", data)
        self.assertTrue(data.endswith(b"}\n"))
        self.assertEqual(data.count(b"\n"), len(_build()) + 2)


if __name__ == "__main__":
    unittest.main()
