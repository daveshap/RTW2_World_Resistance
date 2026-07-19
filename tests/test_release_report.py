from __future__ import annotations

import hashlib
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
REPORT_PATH = ROOT / "validation" / "build_report.json"
PACK_PATH = ROOT / "dist" / "@wr2_world_resistance.pack"


class ReleaseReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = json.loads(REPORT_PATH.read_text(encoding="utf-8"))

    def test_release_and_target(self) -> None:
        self.assertEqual(self.report["release_version"], "0.1.6-beta")
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
        self.assertIn(
            "script/campaign/wr2/wr2_world_resistance.lua", final["paths"]
        )
        self.assertNotIn("lua_scripts/wr2_world_resistance.lua", final["paths"])

    def test_runtime_and_manual_pack_contract(self) -> None:
        runtime = self.report["runtime_contract"]
        self.assertEqual(runtime["pack_filename"], "@wr2_world_resistance.pack")
        self.assertEqual(runtime["director_version"], 8)
        self.assertEqual(runtime["telemetry_schema"], 1)
        self.assertEqual(
            runtime["bootstrap_log_path"], "wr2_world_resistance_bootstrap.log"
        )
        self.assertEqual(
            runtime["diagnostic_log_path"], "data/wr2_world_resistance.log"
        )
        self.assertEqual(
            runtime["director_module_path"],
            "script/campaign/wr2/wr2_world_resistance.lua",
        )
        self.assertEqual(runtime["director_require_name"], "wr2_world_resistance")
        self.assertEqual(
            runtime["listener_registration"],
            "explicit_loader_setup_with_exported_registry",
        )
        self.assertEqual(
            runtime["listener_idempotence"], "registry_and_callback_identity"
        )
        self.assertEqual(
            runtime["listener_partial_retry"],
            "attached_callback_or_repeated_setup",
        )
        self.assertEqual(runtime["interface_binding"], "lazy_existing_episodic_state")
        self.assertEqual(
            runtime["campaign_detection"], "campaign_name_predicate_main_rome"
        )
        self.assertEqual(runtime["initialization_event"], "FirstTickAfterWorldCreated")
        self.assertEqual(
            runtime["initialization_retry"],
            "first_FactionTurnStart_each_campaign_turn",
        )
        self.assertEqual(
            runtime["world_diagnostics"],
            "reasoned_bootstrap_state_and_sink_status",
        )
        self.assertEqual(runtime["diagnostic_log_max_lines"], 1000)
        self.assertEqual(runtime["diagnostic_log_keep_lines"], 800)
        self.assertEqual(runtime["army_measurement"], "general_led_land_forces_only")
        self.assertEqual(
            runtime["ai_army_goal"],
            "min_four_per_region_human_parity_sixteen",
        )
        self.assertEqual(
            runtime["ai_cooperation"],
            "pair_scoped_best_friends_lock_at_tier_85",
        )
        self.assertEqual(
            runtime["visible_attitude_mutation"],
            "read_only_telemetry_no_unsafe_global_bonus",
        )
        self.assertEqual(
            sorted(path.name for path in (ROOT / "dist").glob("*.pack")),
            ["@wr2_world_resistance.pack"],
        )
        loader = (ROOT / "pack_root" / "lua_scripts" / "all_scripted.lua").read_text(
            encoding="utf-8"
        )
        director = (
            ROOT
            / "pack_root"
            / "script"
            / "campaign"
            / "wr2"
            / "wr2_world_resistance.lua"
        ).read_text(encoding="utf-8")
        self.assertIn('WR_BOOT_LOG_PATH = "wr2_world_resistance_bootstrap.log"', loader)
        for milestone in (
            "LOADER_START",
            "DIRECTOR_REQUIRE_OK",
            "DIRECTOR_REQUIRE_ERROR",
            "DIRECTOR_SETUP_TRY",
            "DIRECTOR_SETUP_OK",
            "DIRECTOR_SETUP_PARTIAL",
            "DIRECTOR_SETUP_ERROR",
            "MODULE_PATH_READY",
            "DIRECTOR_ROUTE_OK",
            "EVENT_REGISTRY_READY",
            "LISTENER_OK_",
            "LISTENER_REUSED_",
            "LISTENER_MISSING_",
            "LISTENER_INSERT_ERROR_",
            "LISTENERS_PARTIAL",
            "ENGINE_WAIT",
            "ENGINE_READY",
            "LISTENERS_READY",
            "EVENT_HIT_",
            "WORLD_READY",
            "WORLD_ATTEMPT",
            "WORLD_PROBE_FAIL",
            "WORLD_UNSUPPORTED",
            "WORLD_NO_HUMAN",
            "WORLD_STATE",
            "FACTION_TURN_CONTEXT",
            "DIAGNOSTIC_SINK_READY",
            "DIAGNOSTIC_SINK_ERROR",
        ):
            self.assertIn(milestone, loader + director)
        self.assertIn('local VERSION = 8', director)
        self.assertIn("return director.setup(event_registry)", loader)
        self.assertIn("WR.setup = setup", director)
        self.assertNotIn('rawget(_G, "events")', director)
        self.assertIn(
            "return model:campaign_name(WR.config.supported_campaign)", director
        )
        self.assertNotIn("return model:campaign_name()", director)
        self.assertNotIn('require, "lua_scripts.EpisodicScripting"', director)
        self.assertIn('rawget(_G, "EpisodicScripting")', director)
        self.assertIn('diagnostic_log_path = "data/wr2_world_resistance.log"', director)

    def test_lua_only_hotfix_payload_provenance(self) -> None:
        provenance = self.report["payload_provenance"]
        self.assertEqual(
            provenance["mode"], "lua_only_hotfix_from_rpfm_verified_base"
        )
        self.assertEqual(provenance["base_release"], "0.1.1-beta")
        self.assertEqual(provenance["modified_paths"], ["lua_scripts/all_scripted.lua"])
        self.assertEqual(
            provenance["added_paths"],
            ["script/campaign/wr2/wr2_world_resistance.lua"],
        )
        self.assertEqual(
            provenance["removed_paths"], ["lua_scripts/wr2_world_resistance.lua"]
        )
        self.assertFalse(provenance["rpfm_revalidated_this_hotfix"])
        self.assertEqual(len(provenance["unchanged_payload_sha256"]), 6)

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
        self.assertEqual(reopen["final_tree_paths"], self.report["final_pack"]["paths"])
        self.assertIn("localisation", reopen["exports"])
        self.assertIn("message_events", reopen["exports"])
        self.assertIn("message_event_strings", reopen["exports"])


if __name__ == "__main__":
    unittest.main()
