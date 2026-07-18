from __future__ import annotations

import csv
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MATRIX_JSON = ROOT / "config" / "bundle_matrix.json"
MATRIX_CSV = ROOT / "config" / "bundle_matrix.csv"
FAME_TSV = ROOT / "db_src" / "fame_levels.tsv"


EXPECTED_EFFECT_SCOPE = {
    "rom_tech_module_engineering_construction": "in_all_your_regions",
    "rom_general_local_mod_construction_costs": "in_all_your_regions",
    "rom_building_gdp_mod_all": "in_all_your_regions",
    "rom_tech_civil_economy_tax_mod": "this_faction",
    "rom_force_campaign_mod_recruitment_cost_all": "in_all_your_forces",
    "rom_tech_military_management_upkeep_mod": "in_all_your_forces",
    "rom_tech_military_management_mercenary_cost": "this_faction",
    "rom_tech_military_management_mercenary_upkeep": "in_all_your_forces",
    "rom_building_recruitment_points": "in_all_your_provinces",
    "rom_building_recruitment_points_naval": "in_all_your_sea_regions",
    "rom_force_campaign_mod_replenishment_rate": "in_all_your_regions",
    "rom_force_unit_mod_experience_base": "in_all_your_provinces",
    "rom_force_unit_mod_armour": "in_all_your_forces",
    "rom_force_unit_mod_morale": "in_all_your_forces",
    "rom_force_unit_mod_melee_damage": "in_all_your_forces",
    "rom_force_unit_mod_experience_gain_rate": "in_all_your_forces",
    "rom_building_research_points_mod": "this_faction",
    "rom_building_research_points": "this_faction",
    "rom_faction_public_order_difficulty_level": "in_all_your_provinces",
    "rom_payload_food": "this_faction",
    "rom_province_growth_province_effects": "in_all_your_provinces",
}


class BundleMatrixTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.matrix = json.loads(MATRIX_JSON.read_text(encoding="utf-8"))
        with MATRIX_CSV.open(newline="", encoding="utf-8") as source:
            cls.csv_rows = list(csv.DictReader(source))

    def test_exact_audited_effect_scope_pairs(self) -> None:
        actual = {
            row["effect_key"]: row["effect_scope"]
            for row in self.matrix["effects"]
        }
        self.assertEqual(actual, EXPECTED_EFFECT_SCOPE)

    def test_json_and_csv_are_identical_numeric_sources(self) -> None:
        by_metric = {row["metric"]: row for row in self.csv_rows}
        self.assertEqual(len(by_metric), len(self.matrix["effects"]))
        for effect in self.matrix["effects"]:
            row = by_metric[effect["metric"]]
            self.assertEqual(row["effect_key"], effect["effect_key"])
            self.assertEqual(row["effect_scope"], effect["effect_scope"])
            self.assertEqual(row["unit"], effect["unit"])
            csv_base = [float(row[f"tier_{key}"]) for key in ("00", "20", "40", "65", "85", "100")]
            csv_catchup = [float(row[f"catchup_{key}"]) for key in ("1", "2", "3")]
            self.assertEqual(csv_base, [float(value) for value in effect["base"]])
            self.assertEqual(csv_catchup, [float(value) for value in effect["catchup"]])
            expected_stage = effect.get(
                "advancement_stage", self.matrix["advancement_stage"]
            )
            self.assertEqual(row["advancement_stage"], expected_stage)

    def test_absolute_bundle_contract(self) -> None:
        contract = self.matrix["application_contract"]
        self.assertEqual(contract["eligibility"], "every active non-human faction")
        self.assertFalse(contract["war_or_relationship_filter"])
        self.assertEqual(
            contract["base_bundle_keys"],
            [
                "wr2_wr_ai_tier_00",
                "wr2_wr_ai_tier_20",
                "wr2_wr_ai_tier_40",
                "wr2_wr_ai_tier_65",
                "wr2_wr_ai_tier_85",
                "wr2_wr_ai_tier_100",
            ],
        )
        self.assertEqual(contract["base_pressure_thresholds"], [0, 20, 40, 65, 85, 100])
        self.assertEqual(
            contract["catchup_bundle_keys"],
            ["wr2_wr_ai_catchup_1", "wr2_wr_ai_catchup_2", "wr2_wr_ai_catchup_3"],
        )
        for effect in self.matrix["effects"]:
            self.assertEqual(len(effect["base"]), 6)
            self.assertEqual(len(effect["catchup"]), 3)
            self.assertAlmostEqual(
                effect["base"][-1] + effect["catchup"][-1],
                effect["max_tier_100_plus_catchup_3"],
            )

    def test_owned_cost_reductions_never_exceed_ninety_percent(self) -> None:
        for effect in self.matrix["effects"]:
            if effect["metric"] in {
                "construction_cost",
                "recruitment_cost",
                "unit_upkeep",
                "mercenary_recruitment_cost",
                "mercenary_upkeep",
            }:
                self.assertGreaterEqual(min(effect["base"]), -90)
                self.assertEqual(effect["catchup"], [0, 0, 0])


class FameLevelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        with FAME_TSV.open(newline="", encoding="utf-8") as source:
            reader = csv.DictReader(
                (line for line in source if not line.startswith("#")), delimiter="\t"
            )
            cls.rows = list(reader)

    def test_exactly_eight_unique_main_rome_levels(self) -> None:
        self.assertEqual(len(self.rows), 8)
        keys = [(row["campaign"], int(row["level"])) for row in self.rows]
        self.assertEqual(len(keys), len(set(keys)), "duplicate fame rows can reset caps")
        self.assertEqual(keys, [("main_rome", level) for level in range(8)])

    def test_human_progression_is_preserved(self) -> None:
        self.assertEqual(
            [int(row["player_prestige"]) for row in self.rows],
            [0, 4, 12, 24, 40, 60, 84, 112],
        )
        self.assertEqual(
            [int(row["army_cap"]) for row in self.rows],
            [3, 4, 6, 8, 10, 12, 14, 16],
        )

    def test_ai_resolves_to_final_cap_at_nonnegative_prestige(self) -> None:
        self.assertEqual(
            [int(row["ai_prestige"]) for row in self.rows],
            [-7, -6, -5, -4, -3, -2, -1, 0],
        )
        self.assertEqual(int(self.rows[-1]["army_cap"]), 16)


if __name__ == "__main__":
    unittest.main()
