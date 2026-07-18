from __future__ import annotations

import hashlib
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
REPORT_PATH = ROOT / "validation" / "build_report.json"
PACK_PATH = ROOT / "dist" / "wr2_world_resistance.pack"


class ReleaseReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = json.loads(REPORT_PATH.read_text(encoding="utf-8"))

    def test_release_and_target(self) -> None:
        self.assertEqual(self.report["release_version"], "0.1.1-beta")
        self.assertEqual(self.report["target"]["game"], "rome_2")
        self.assertEqual(self.report["target"]["campaign"], "main_rome")

    def test_pack_hash_size_and_path_contract(self) -> None:
        payload = PACK_PATH.read_bytes()
        final = self.report["final_pack"]
        self.assertEqual(hashlib.sha256(payload).hexdigest(), final["sha256"])
        self.assertEqual(len(payload), final["pack_size"])
        self.assertTrue(final["valid"])
        self.assertEqual(final["file_count"], 8)
        self.assertEqual(len(final["paths"]), 8)
        self.assertIn("text/db/wr2_world_resistance.loc", final["paths"])

    def test_observability_contract(self) -> None:
        contract = self.report["validated_contract"]
        self.assertEqual(contract["message_event_rows"], 6)
        self.assertEqual(contract["message_event_string_rows"], 24)
        self.assertEqual(contract["localisation_rows"], 30)
        self.assertEqual(
            contract["custom_event_keys"],
            [f"custom_event_2318200{index}" for index in range(6)],
        )
        self.assertEqual(
            contract["message_event_cultures"],
            ["rom_Barbarian", "rom_Eastern", "rom_Hellenistic", "rom_Roman"],
        )

    def test_reported_inputs_match_release_sources(self) -> None:
        inputs = self.report["inputs"]
        for relative, expected in inputs["lua_sha256"].items():
            actual = hashlib.sha256((ROOT / "pack_root" / relative).read_bytes()).hexdigest()
            self.assertEqual(actual, expected)
        source_hashes = {
            "fame_tsv_sha256": ROOT / "db_src" / "fame_levels.tsv",
            "message_events_tsv_sha256": ROOT / "db_src" / "message_events.tsv",
            "message_event_strings_tsv_sha256": (
                ROOT / "db_src" / "message_event_strings.tsv"
            ),
            "localisation_tsv_sha256": ROOT / "db_src" / "wr2_world_resistance.loc.tsv",
        }
        for field, path in source_hashes.items():
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), inputs[field])

    def test_core_balance_contract_is_unchanged(self) -> None:
        contract = self.report["validated_contract"]
        self.assertEqual(contract["effect_count"], 21)
        self.assertEqual(contract["effect_bundle_rows"], 9)
        self.assertEqual(contract["bundle_effect_rows"], 162)
        self.assertEqual(contract["fame_rows"], 8)
        self.assertEqual(contract["army_caps"], [3, 4, 6, 8, 10, 12, 14, 16])

    def test_rpfm_reopen_has_no_unexpected_diagnostic(self) -> None:
        reopen = self.report["rpfm_reopen"]
        self.assertEqual(reopen["unexpected_diagnostics"], [])
        self.assertIn("localisation", reopen["exports"])
        self.assertIn("message_events", reopen["exports"])
        self.assertIn("message_event_strings", reopen["exports"])


if __name__ == "__main__":
    unittest.main()
