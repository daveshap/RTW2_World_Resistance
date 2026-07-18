#!/usr/bin/env python3
"""Build and structurally validate WR2 World Resistance.

The build is deliberately two-stage:

1. RPFM 5, using the current Rome II schema, imports the validated TSV source
   and produces the opaque binary DB payloads.
2. The local PFH4 writer strips RPFM-only metadata, gives each DB table a stable
   path-derived GUID, adds the localization and two Lua files, and emits a
   deterministic eight-file Mod pack with no dependencies or flags.

The final pack is then reopened by a fresh RPFM process, every DB table is
exported again, and diagnostics are recorded.  This keeps RPFM authoritative
for Total War DB encoding while making the shipped container minimal and
byte-for-byte reproducible.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import sys
import tempfile
from typing import Any, Iterable, Sequence
import uuid

try:
    from .pfh4 import HEADER, PackFormatError, read_pack, validate_pack, write_pack_file
    from .rpfm_ws_client import RpfmWsError, RpfmWsSession
except ImportError:  # Direct execution from the tools directory.
    from pfh4 import HEADER, PackFormatError, read_pack, validate_pack, write_pack_file
    from rpfm_ws_client import RpfmWsError, RpfmWsSession


BUILD_TOOL_VERSION = "1.1.0"
RELEASE_VERSION = "0.1.1-beta"
GAME_KEY = "rome_2"
CAMPAIGN_KEY = "main_rome"

BASE_KEYS = [
    "wr2_wr_ai_tier_00",
    "wr2_wr_ai_tier_20",
    "wr2_wr_ai_tier_40",
    "wr2_wr_ai_tier_65",
    "wr2_wr_ai_tier_85",
    "wr2_wr_ai_tier_100",
]
BASE_THRESHOLDS = [0, 20, 40, 65, 85, 100]
CATCHUP_KEYS = [
    "wr2_wr_ai_catchup_1",
    "wr2_wr_ai_catchup_2",
    "wr2_wr_ai_catchup_3",
]

# Metric -> (effect key, effect scope, advancement stage).  The list is an
# allowlist, not merely documentation: unknown or missing effects stop a build.
EXPECTED_EFFECTS = {
    "construction_turns": (
        "rom_tech_module_engineering_construction",
        "in_all_your_regions",
        "start_turn_completed",
    ),
    "construction_cost": (
        "rom_general_local_mod_construction_costs",
        "in_all_your_regions",
        "start_turn_completed",
    ),
    "building_gdp": (
        "rom_building_gdp_mod_all",
        "in_all_your_regions",
        "start_turn_completed",
    ),
    "tax_income": (
        "rom_tech_civil_economy_tax_mod",
        "this_faction",
        "start_turn_completed",
    ),
    "recruitment_cost": (
        "rom_force_campaign_mod_recruitment_cost_all",
        "in_all_your_forces",
        "start_turn_completed",
    ),
    "unit_upkeep": (
        "rom_tech_military_management_upkeep_mod",
        "in_all_your_forces",
        "start_turn_completed",
    ),
    "mercenary_recruitment_cost": (
        "rom_tech_military_management_mercenary_cost",
        "this_faction",
        "start_turn_completed",
    ),
    "mercenary_upkeep": (
        "rom_tech_military_management_mercenary_upkeep",
        "in_all_your_forces",
        "start_turn_completed",
    ),
    "land_recruitment_capacity": (
        "rom_building_recruitment_points",
        "in_all_your_provinces",
        "start_turn_completed",
    ),
    "naval_recruitment_capacity": (
        "rom_building_recruitment_points_naval",
        "in_all_your_sea_regions",
        "start_turn_completed",
    ),
    "replenishment": (
        "rom_force_campaign_mod_replenishment_rate",
        "in_all_your_regions",
        "start_turn_completed",
    ),
    "recruit_rank": (
        "rom_force_unit_mod_experience_base",
        "in_all_your_provinces",
        "start_turn_initiated",
    ),
    "army_armour": (
        "rom_force_unit_mod_armour",
        "in_all_your_forces",
        "start_turn_completed",
    ),
    "army_morale": (
        "rom_force_unit_mod_morale",
        "in_all_your_forces",
        "start_turn_completed",
    ),
    "army_melee_damage": (
        "rom_force_unit_mod_melee_damage",
        "in_all_your_forces",
        "start_turn_initiated",
    ),
    "experience_gain": (
        "rom_force_unit_mod_experience_gain_rate",
        "in_all_your_forces",
        "start_turn_completed",
    ),
    "research_rate": (
        "rom_building_research_points_mod",
        "this_faction",
        "start_turn_completed",
    ),
    "research_points": (
        "rom_building_research_points",
        "this_faction",
        "start_turn_completed",
    ),
    "public_order": (
        "rom_faction_public_order_difficulty_level",
        "in_all_your_provinces",
        "start_turn_completed",
    ),
    "food": ("rom_payload_food", "this_faction", "start_turn_completed"),
    "province_growth": (
        "rom_province_growth_province_effects",
        "in_all_your_provinces",
        "start_turn_completed",
    ),
}

EFFECT_BUNDLE_HEADER = [
    "key",
    "localised_description",
    "localised_title",
    "ui_icon",
    "bundle_target",
]
JUNCTION_HEADER = [
    "effect_bundle_key",
    "effect_key",
    "effect_scope",
    "value",
    "advancement_stage",
]
FAME_HEADER = [
    "level",
    "campaign",
    "ai_prestige",
    "army_cap",
    "champion_cap",
    "dignitary_cap",
    "navy_cap",
    "player_prestige",
    "province_initiative_cap",
    "spy_cap",
    "description_lookup",
    "effect_bundle",
]
MESSAGE_EVENTS_HEADER = [
    "event",
    "instant_open",
    "layout",
    "requires_response",
    "priority",
]
MESSAGE_EVENT_STRINGS_HEADER = [
    "event",
    "optional_campaign_key",
    "culture",
    "optional_subculture",
    "text",
    "image",
    "icon",
    "sound_event",
]
LOC_HEADER = ["key", "text", "tooltip"]

STATUS_EVENT_KEYS = [f"custom_event_2318200{index}" for index in range(6)]
STATUS_TEXT_KEYS = [
    "wr2_wr_status_00",
    "wr2_wr_status_20",
    "wr2_wr_status_40",
    "wr2_wr_status_65",
    "wr2_wr_status_85",
    "wr2_wr_status_100",
]
STATUS_CULTURES = [
    "rom_Barbarian",
    "rom_Eastern",
    "rom_Hellenistic",
    "rom_Roman",
]

DB_SPECS = [
    (
        "effect_bundles",
        "effect_bundles_tables",
        1,
        "db/effect_bundles_tables/wr2_world_resistance",
    ),
    (
        "effect_bundles_to_effects",
        "effect_bundles_to_effects_junctions_tables",
        2,
        "db/effect_bundles_to_effects_junctions_tables/wr2_world_resistance",
    ),
    (
        "fame_levels",
        "fame_levels_tables",
        4,
        "db/fame_levels_tables/wr2_world_resistance",
    ),
    (
        "message_events",
        "message_events_tables",
        1,
        "db/message_events_tables/wr2_world_resistance",
    ),
    (
        "message_event_strings",
        "message_event_strings_tables",
        3,
        "db/message_event_strings_tables/wr2_world_resistance",
    ),
]

LOC_NAME = "wr2_world_resistance.loc"
LOC_PATH = "text/db/wr2_world_resistance.loc"

LUA_PATHS = [
    "lua_scripts/all_scripted.lua",
    "lua_scripts/wr2_world_resistance.lua",
]
REQUIRED_PACK_PATHS = sorted(
    [spec[3] for spec in DB_SPECS] + [LOC_PATH] + LUA_PATHS,
    key=lambda path: (path.replace("/", "\\").lower(), path.replace("/", "\\")),
)
RPFM_RESERVED_PATHS = {
    "dependencies_manager_v2.rpfm_reserved",
    "notes.rpfm_reserved",
    "settings.rpfm_reserved",
}

# Exact decoded, backward-compatible main_rome v4 rows used by this release.
# The (level, campaign) key must occur exactly once; duplicate rows are known
# to reset caps at Imperium 8.
EXPECTED_FAME_ROWS = [
    ["0", "main_rome", "-7", "3", "1", "1", "1", "0", "0", "1", "imperium_tooltip_01", "imperium_1"],
    ["1", "main_rome", "-6", "4", "1", "1", "2", "4", "1", "1", "imperium_tooltip_03", "imperium_2"],
    ["2", "main_rome", "-5", "6", "2", "2", "3", "12", "1", "2", "imperium_tooltip_04", "imperium_3"],
    ["3", "main_rome", "-4", "8", "2", "2", "4", "24", "2", "2", "imperium_tooltip_05", "imperium_4"],
    ["4", "main_rome", "-3", "10", "3", "3", "5", "40", "2", "3", "imperium_tooltip_06", "imperium_5"],
    ["5", "main_rome", "-2", "12", "3", "3", "6", "60", "3", "3", "imperium_tooltip_07", "imperium_6"],
    ["6", "main_rome", "-1", "14", "4", "4", "7", "84", "4", "4", "imperium_tooltip_08", "imperium_7"],
    ["7", "main_rome", "0", "16", "5", "5", "8", "112", "5", "5", "imperium_tooltip_09", "imperium_8"],
]


class BuildError(RuntimeError):
    """Raised when an input or generated artifact violates the build contract."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _atomic_write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as output:
            output.write(text)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise


def _atomic_copy(source: Path, destination: Path) -> None:
    """Copy across filesystems and atomically replace only inside the target dir."""

    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent
    )
    temporary = Path(temporary_name)
    try:
        with source.open("rb") as input_file, os.fdopen(descriptor, "wb") as output_file:
            shutil.copyfileobj(input_file, output_file, length=1024 * 1024)
            output_file.flush()
            os.fsync(output_file.fileno())
        os.replace(temporary, destination)
    except BaseException:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise


def _tsv_text(header: list[str], metadata: str, rows: Iterable[Iterable[object]]) -> str:
    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, delimiter="\t", lineterminator="\n")
    writer.writerow(header)
    writer.writerow([metadata] + [""] * (len(header) - 1))
    writer.writerows(rows)
    return buffer.getvalue()


def _parse_tsv(path: Path) -> tuple[list[str], str, list[list[str]]]:
    with path.open("r", encoding="utf-8", newline="") as source:
        rows = list(csv.reader(source, delimiter="\t"))
    if len(rows) < 2:
        raise BuildError(f"TSV lacks its two header rows: {path}")
    header = rows[0]
    metadata = rows[1][0] if rows[1] else ""
    if len(rows[1]) != len(header) or any(rows[1][1:]):
        raise BuildError(f"malformed RPFM metadata row in {path}")
    for number, row in enumerate(rows[2:], start=3):
        if len(row) != len(header):
            raise BuildError(
                f"TSV row {number} has {len(row)} fields, expected {len(header)}: {path}"
            )
    return header, metadata, rows[2:]


def _number(value: object, label: str) -> float | int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise BuildError(f"{label} must be numeric")
    if not math.isfinite(float(value)):
        raise BuildError(f"{label} must be finite")
    return value


def _number_text(value: object) -> str:
    number = _number(value, "effect value")
    if float(number).is_integer():
        return str(int(number))
    return format(float(number), ".9g")


def _validate_csv_crosscheck(project: Path, matrix: dict[str, Any]) -> None:
    csv_path = project / "config" / "bundle_matrix.csv"
    with csv_path.open("r", encoding="utf-8", newline="") as source:
        rows = list(csv.DictReader(source))
    effects = matrix["effects"]
    if len(rows) != len(effects):
        raise BuildError(
            f"bundle_matrix.csv has {len(rows)} effects, JSON has {len(effects)}"
        )
    base_columns = ["tier_00", "tier_20", "tier_40", "tier_65", "tier_85", "tier_100"]
    catchup_columns = ["catchup_1", "catchup_2", "catchup_3"]
    for index, (csv_row, effect) in enumerate(zip(rows, effects, strict=True), start=1):
        stage = effect.get("advancement_stage", matrix["advancement_stage"])
        expected_scalars = {
            "metric": effect["metric"],
            "effect_key": effect["effect_key"],
            "effect_scope": effect["effect_scope"],
            "unit": effect["unit"],
            "advancement_stage": stage,
        }
        for column, expected in expected_scalars.items():
            if csv_row.get(column) != str(expected):
                raise BuildError(
                    f"matrix CSV/JSON mismatch at effect {index}, column {column}: "
                    f"{csv_row.get(column)!r} != {expected!r}"
                )
        expected_values = list(effect["base"]) + list(effect["catchup"])
        for column, expected in zip(base_columns + catchup_columns, expected_values, strict=True):
            if csv_row.get(column) != _number_text(expected):
                raise BuildError(
                    f"matrix CSV/JSON mismatch at effect {index}, column {column}"
                )
        if csv_row.get("max_tier_100_plus_catchup_3") != _number_text(
            effect["max_tier_100_plus_catchup_3"]
        ):
            raise BuildError(
                f"matrix CSV/JSON mismatch at effect {index}, maximum composite"
            )


def validate_matrix(project: Path) -> dict[str, Any]:
    matrix_path = project / "config" / "bundle_matrix.json"
    matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    if matrix.get("schema_version") != 1:
        raise BuildError("unsupported bundle matrix schema_version")
    if matrix.get("advancement_stage") != "start_turn_completed":
        raise BuildError("unexpected default advancement stage")
    if matrix.get("bundle_target") != "faction":
        raise BuildError("effect bundles must target faction")

    contract = matrix.get("application_contract", {})
    expected_contract = {
        "eligibility": "every active non-human faction",
        "war_or_relationship_filter": False,
        "base_bundle_mode": "exactly_one_exclusive_absolute_tier",
        "catchup_bundle_mode": "zero_or_one_exclusive_absolute_level",
        "zero_value_rows": "omit",
        "base_bundle_keys": BASE_KEYS,
        "base_pressure_thresholds": BASE_THRESHOLDS,
        "catchup_bundle_keys": CATCHUP_KEYS,
    }
    for key, expected in expected_contract.items():
        if contract.get(key) != expected:
            raise BuildError(f"invalid application_contract.{key}: {contract.get(key)!r}")

    effects = matrix.get("effects")
    if not isinstance(effects, list) or len(effects) != 21:
        raise BuildError("bundle matrix must contain exactly 21 effects")
    metrics = [effect.get("metric") for effect in effects if isinstance(effect, dict)]
    if len(metrics) != 21 or len(set(metrics)) != 21 or set(metrics) != set(EXPECTED_EFFECTS):
        raise BuildError("bundle matrix metrics do not match the 21-effect allowlist")

    for effect in effects:
        metric = effect["metric"]
        expected_key, expected_scope, expected_stage = EXPECTED_EFFECTS[metric]
        actual = (
            effect.get("effect_key"),
            effect.get("effect_scope"),
            effect.get("advancement_stage", matrix["advancement_stage"]),
        )
        if actual != (expected_key, expected_scope, expected_stage):
            raise BuildError(f"unverified key/scope/stage for {metric}: {actual!r}")
        base = effect.get("base")
        catchup = effect.get("catchup")
        if not isinstance(base, list) or len(base) != 6:
            raise BuildError(f"{metric}.base must have six absolute tiers")
        if not isinstance(catchup, list) or len(catchup) != 3:
            raise BuildError(f"{metric}.catchup must have three absolute levels")
        values = [
            _number(value, f"{metric} value") for value in list(base) + list(catchup)
        ]
        maximum = _number(
            effect.get("max_tier_100_plus_catchup_3"), f"{metric} composite"
        )
        if not math.isclose(float(maximum), float(base[-1]) + float(catchup[-1])):
            raise BuildError(f"incorrect Tier100 + Catchup3 composite for {metric}")
        # Absolute base tiers must become no weaker as human pressure grows.
        direction = -1 if float(base[-1]) < 0 else 1
        signed = [direction * float(value) for value in base]
        if any(later < earlier for earlier, later in zip(signed, signed[1:])):
            raise BuildError(f"base tiers are not monotonic for {metric}")
        if any(not math.isfinite(float(value)) for value in values):
            raise BuildError(f"non-finite value for {metric}")

    # Cost/time reducers may exist only in the exclusive base bundle and never
    # go below the mod-owned ceiling.
    reduction_limits = {
        "construction_turns": -7,
        "construction_cost": -90,
        "recruitment_cost": -90,
        "unit_upkeep": -90,
        "mercenary_recruitment_cost": -90,
        "mercenary_upkeep": -90,
    }
    by_metric = {effect["metric"]: effect for effect in effects}
    for metric, floor in reduction_limits.items():
        effect = by_metric[metric]
        if min(effect["base"]) < floor or any(value != 0 for value in effect["catchup"]):
            raise BuildError(f"unsafe cost/time reduction stack for {metric}")

    composite_caps = {
        "replenishment": 50,
        "recruit_rank": 9,
        "army_armour": 10,
        "army_morale": 10,
        "army_melee_damage": 10,
        "experience_gain": 15,
    }
    for metric, ceiling in composite_caps.items():
        if float(by_metric[metric]["max_tier_100_plus_catchup_3"]) > ceiling:
            raise BuildError(f"unsafe maximum composite for {metric}")

    _validate_csv_crosscheck(project, matrix)
    return matrix


def validate_fame(path: Path) -> list[list[str]]:
    header, metadata, rows = _parse_tsv(path)
    expected_metadata = "#fame_levels_tables;4;db/fame_levels_tables/wr2_world_resistance"
    if header != FAME_HEADER or metadata != expected_metadata:
        raise BuildError("fame_levels.tsv is not the expected pre-PANTHEON v4 table")
    if rows != EXPECTED_FAME_ROWS:
        raise BuildError("fame_levels.tsv rows differ from the exact eight-row stable contract")
    keys = [(row[0], row[1]) for row in rows]
    if len(keys) != 8 or len(set(keys)) != 8:
        raise BuildError("fame_levels must have exactly eight unique (level, campaign) keys")
    if [int(row[0]) for row in rows] != list(range(8)):
        raise BuildError("fame levels must be exactly 0 through 7")
    if any(row[1] != CAMPAIGN_KEY for row in rows):
        raise BuildError("fame table contains a campaign other than main_rome")
    return rows


def validate_observability_sources(project: Path) -> dict[str, Path]:
    sources = {
        "message_events": project / "db_src" / "message_events.tsv",
        "message_event_strings": project / "db_src" / "message_event_strings.tsv",
        "localisation": project / "db_src" / "wr2_world_resistance.loc.tsv",
    }

    event_header, event_metadata, event_rows = _parse_tsv(sources["message_events"])
    if event_header != MESSAGE_EVENTS_HEADER:
        raise BuildError("message_events.tsv has an unexpected header")
    if event_metadata != (
        "#message_events_tables;1;db/message_events_tables/wr2_world_resistance"
    ):
        raise BuildError("message_events.tsv has unexpected RPFM metadata")
    expected_events = [
        [event, "true", "standard", "true", "100"] for event in STATUS_EVENT_KEYS
    ]
    if event_rows != expected_events:
        raise BuildError("message_events.tsv differs from the six-event UI contract")
    if any(re.fullmatch(r"custom_event_[0-9]+", row[0]) is None for row in event_rows):
        raise BuildError("Rome II custom event keys must be custom_event_ followed by digits")

    strings_header, strings_metadata, strings_rows = _parse_tsv(
        sources["message_event_strings"]
    )
    if strings_header != MESSAGE_EVENT_STRINGS_HEADER:
        raise BuildError("message_event_strings.tsv has an unexpected header")
    if strings_metadata != (
        "#message_event_strings_tables;3;"
        "db/message_event_strings_tables/wr2_world_resistance"
    ):
        raise BuildError("message_event_strings.tsv has unexpected RPFM metadata")
    expected_strings = [
        [
            event,
            "",
            culture,
            "",
            text_key,
            "rom_land_victory.png",
            "rom_event_military.png",
            "campaign_ui_message_neutral",
        ]
        for event, text_key in zip(STATUS_EVENT_KEYS, STATUS_TEXT_KEYS, strict=True)
        for culture in STATUS_CULTURES
    ]
    if strings_rows != expected_strings:
        raise BuildError("message_event_strings.tsv differs from the culture-complete UI contract")
    string_keys = [(row[0], row[1], row[2], row[3]) for row in strings_rows]
    if len(string_keys) != len(set(string_keys)):
        raise BuildError("message_event_strings contains duplicate composite keys")

    loc_header, loc_metadata, loc_rows = _parse_tsv(sources["localisation"])
    if loc_header != LOC_HEADER or loc_metadata != f"#Loc;1;{LOC_PATH}":
        raise BuildError("World Resistance Loc source has an unexpected header or metadata")
    loc_by_key = {row[0]: row for row in loc_rows}
    if len(loc_rows) != 30 or len(loc_by_key) != 30:
        raise BuildError("World Resistance Loc must contain exactly 30 unique rows")
    expected_loc_keys = {
        f"message_event_text_text_{text_key}" for text_key in STATUS_TEXT_KEYS
    }
    expected_loc_keys.update(
        f"message_event_strings_title_{event}{culture}"
        for event in STATUS_EVENT_KEYS
        for culture in STATUS_CULTURES
    )
    if set(loc_by_key) != expected_loc_keys:
        raise BuildError("World Resistance Loc keys do not close every title/body reference")
    if any(not row[1] or row[2] != "true" for row in loc_rows):
        raise BuildError("World Resistance Loc contains an empty string or invalid tooltip flag")
    for text_key in STATUS_TEXT_KEYS:
        body = loc_by_key[f"message_event_text_text_{text_key}"][1]
        if "data/wr2_world_resistance.log" not in body or "No data leaves" not in body:
            raise BuildError("status body must disclose the local diagnostics path and locality")

    return sources


def generate_effect_tsvs(project: Path, matrix: dict[str, Any]) -> dict[str, Path]:
    db_source = project / "db_src"
    bundle_path = db_source / "effect_bundles.tsv"
    junction_path = db_source / "effect_bundles_to_effects.tsv"

    bundle_rows = [[key, "", "", "", "faction"] for key in BASE_KEYS + CATCHUP_KEYS]
    bundle_text = _tsv_text(
        EFFECT_BUNDLE_HEADER,
        "#effect_bundles_tables;1;db/effect_bundles_tables/wr2_world_resistance",
        bundle_rows,
    )

    junction_rows: list[list[str]] = []
    for key, index in zip(BASE_KEYS, range(6), strict=True):
        for effect in matrix["effects"]:
            value = effect["base"][index]
            if value == 0:
                continue
            stage = effect.get("advancement_stage", matrix["advancement_stage"])
            junction_rows.append(
                [key, effect["effect_key"], effect["effect_scope"], _number_text(value), stage]
            )
    for key, index in zip(CATCHUP_KEYS, range(3), strict=True):
        for effect in matrix["effects"]:
            value = effect["catchup"][index]
            if value == 0:
                continue
            stage = effect.get("advancement_stage", matrix["advancement_stage"])
            junction_rows.append(
                [key, effect["effect_key"], effect["effect_scope"], _number_text(value), stage]
            )
    if len(junction_rows) != 162:
        raise BuildError(f"expected 162 nonzero bundle-effect rows, generated {len(junction_rows)}")
    if any(row[3] in ("0", "-0", "0.0") for row in junction_rows):
        raise BuildError("zero-valued junction row was not omitted")
    junction_text = _tsv_text(
        JUNCTION_HEADER,
        "#effect_bundles_to_effects_junctions_tables;2;"
        "db/effect_bundles_to_effects_junctions_tables/wr2_world_resistance",
        junction_rows,
    )
    _atomic_write_text(bundle_path, bundle_text)
    _atomic_write_text(junction_path, junction_text)
    sources = {
        "effect_bundles": bundle_path,
        "effect_bundles_to_effects": junction_path,
        "fame_levels": project / "db_src" / "fame_levels.tsv",
    }
    sources.update(validate_observability_sources(project))
    return sources


def _copy_schema(source: Path, home: Path) -> Path:
    if not source.is_file():
        raise BuildError(f"Rome II RPFM schema not found: {source}")
    target = home / ".config" / "rpfm" / "schemas" / "schema_rom2.ron"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    return target


def _new_db_table(
    session: RpfmWsSession,
    pack_key: str,
    filename: str,
    table: str,
    version: int,
    internal_path: str,
) -> None:
    response = session.call(
        {"NewPackedFile": [pack_key, internal_path, {"DB": [filename, table, version]}]}
    )
    if response != "Success":
        raise BuildError(f"RPFM failed to create {internal_path}: {response!r}")


def _new_loc_file(session: RpfmWsSession, pack_key: str) -> None:
    response = session.call(
        {"NewPackedFile": [pack_key, LOC_PATH, {"Loc": LOC_NAME}]}
    )
    if response != "Success":
        raise BuildError(f"RPFM failed to create {LOC_PATH}: {response!r}")


def _import_tsv(session: RpfmWsSession, pack_key: str, internal_path: str, source: Path) -> None:
    response = session.call({"ImportTSV": [pack_key, internal_path, str(source.resolve())]})
    if not (isinstance(response, dict) and "RFileDecoded" in response):
        raise BuildError(f"RPFM failed to import {source}: {response!r}")


def _collect_report_types(value: object) -> list[str]:
    found: list[str] = []
    if isinstance(value, dict):
        for key, item in value.items():
            if key == "report_type" and isinstance(item, str):
                found.append(item)
            else:
                found.extend(_collect_report_types(item))
    elif isinstance(value, list):
        for item in value:
            found.extend(_collect_report_types(item))
    return found


def _normalize_rpfm_stage(stage_pack: Path, output: Path, project: Path) -> dict[str, object]:
    blob = bytearray(stage_pack.read_bytes())
    if len(blob) < HEADER.size:
        raise BuildError("RPFM stage pack has a truncated PFH4 header")
    magic, type_and_flags, dependencies, dependency_size, _, _, _ = HEADER.unpack_from(blob)
    if magic != b"PFH4" or type_and_flags != 3:
        raise BuildError("RPFM stage pack is not an unflagged PFH4 Mod")
    if dependencies != 0 or dependency_size != 0:
        raise BuildError("RPFM stage pack unexpectedly declares dependencies")

    # RPFM writes the current timestamp.  Zero only this documented PFH4 header
    # field so the strict reader can validate and extract opaque DB payloads.
    struct.pack_into("<I", blob, 24, 0)
    archive = read_pack(blob)
    all_entries = archive.as_dict()
    database_paths = {spec[3] for spec in DB_SPECS}
    encoded_paths = database_paths | {LOC_PATH}
    if not encoded_paths.issubset(all_entries):
        missing = sorted(encoded_paths.difference(all_entries))
        raise BuildError(f"RPFM stage pack is missing encoded payloads: {missing}")
    unexpected = set(all_entries).difference(encoded_paths).difference(RPFM_RESERVED_PATHS)
    if unexpected:
        raise BuildError(f"RPFM stage pack has unexpected files: {sorted(unexpected)}")

    final_entries = {
        path: _canonicalize_db_guid(all_entries[path], path) for path in database_paths
    }
    final_entries[LOC_PATH] = all_entries[LOC_PATH]
    lua_root = project / "pack_root"
    actual_lua: list[str] = []
    for item in lua_root.rglob("*"):
        if item.is_symlink():
            raise BuildError(f"symlink forbidden in pack_root: {item}")
        if item.is_file():
            actual_lua.append(item.relative_to(lua_root).as_posix())
    if sorted(actual_lua) != sorted(LUA_PATHS):
        raise BuildError(
            f"pack_root must contain exactly the two loader/director Lua files; found {actual_lua}"
        )
    for path in LUA_PATHS:
        final_entries[path] = (lua_root / path).read_bytes()

    write_pack_file(output, final_entries)
    report = validate_pack(output.read_bytes())
    if report["paths"] != REQUIRED_PACK_PATHS or report["file_count"] != 8:
        raise BuildError(f"final pack paths differ from the exact eight-file contract: {report['paths']}")
    return report


def _canonicalize_db_guid(payload: bytes, internal_path: str) -> bytes:
    """Replace only RPFM's random table GUID with a stable valid UUID.

    Rome II DB tables begin with the UTF-16 GUID marker used by RPFM.  Creating
    a new table otherwise produces a random UUID on every build even when all
    rows are identical.  The table body remains exactly RPFM-encoded, and the
    fresh-RPFM reopen/export pass below validates the normalized result.
    """

    marker = b"\xfd\xfe\xfc\xff"
    if len(payload) < 82 or payload[:4] != marker or payload[4:6] != b"\x24\x00":
        raise BuildError(f"unexpected Rome II DB GUID header in {internal_path}")
    if payload[78:82] != b"\xfc\xfd\xfe\xff":
        raise BuildError(f"unexpected post-GUID DB marker in {internal_path}")
    try:
        original = payload[6:78].decode("utf-16-le")
        uuid.UUID(original)
    except (UnicodeDecodeError, ValueError) as error:
        raise BuildError(f"invalid RPFM-generated table GUID in {internal_path}") from error
    stable = str(
        uuid.uuid5(uuid.NAMESPACE_URL, f"https://wr2.world-resistance.invalid/{internal_path}")
    ).encode("utf-16-le")
    if len(stable) != 72:
        raise AssertionError("canonical UUID does not occupy 36 UTF-16 code units")
    normalized = bytearray(payload)
    normalized[6:78] = stable
    return bytes(normalized)


def _rows_by_name(paths: dict[str, Path]) -> dict[str, list[list[str]]]:
    result: dict[str, list[list[str]]] = {}
    for name, path in paths.items():
        _, _, rows = _parse_tsv(path)
        if name == "effect_bundles_to_effects":
            normalized: list[list[str]] = []
            for row in rows:
                copy = list(row)
                try:
                    copy[3] = _number_text(float(copy[3]))
                except (IndexError, ValueError) as error:
                    raise BuildError(f"invalid F32 value in {path}: {row!r}") from error
                normalized.append(copy)
            rows = normalized
        result[name] = rows
    return result


def _rpfm_encode(
    server: Path,
    home: Path,
    library_path: str | None,
    tsv_paths: dict[str, Path],
    stage_pack: Path,
) -> dict[str, object]:
    with RpfmWsSession(server, home=home, library_path=library_path) as session:
        game = session.call({"SetGameSelected": [GAME_KEY, False]})
        result = session.call("NewPack")
        if not (isinstance(result, dict) and isinstance(result.get("String"), str)):
            raise BuildError(f"RPFM did not create a pack: {result!r}")
        pack_key = result["String"]
        if session.call({"SetPackFileType": [pack_key, "Mod"]}) != "Success":
            raise BuildError("RPFM did not accept Mod pack type")
        for filename, table, version, internal_path in DB_SPECS:
            _new_db_table(session, pack_key, filename, table, version, internal_path)
            _import_tsv(session, pack_key, internal_path, tsv_paths[filename])
        _new_loc_file(session, pack_key)
        _import_tsv(session, pack_key, LOC_PATH, tsv_paths["localisation"])
        diagnostics = session.call({"DiagnosticsCheck": [[], False]})
        saved = session.call({"SavePackAs": [pack_key, str(stage_pack.resolve())]})
        if not (isinstance(saved, dict) and "ContainerInfo" in saved):
            raise BuildError(f"RPFM did not save the staging pack: {saved!r}")
        container = saved["ContainerInfo"]
        return {
            "game_selection": game,
            "diagnostics": diagnostics,
            "container": {
                "pfh_version": container.get("pfh_version"),
                "pfh_file_type": container.get("pfh_file_type"),
                "bitmask": container.get("bitmask"),
                "compress": container.get("compress"),
            },
        }


def _rpfm_reopen_validate(
    server: Path,
    home: Path,
    library_path: str | None,
    output: Path,
    expected_tsvs: dict[str, Path],
    export_root: Path,
) -> dict[str, object]:
    export_root.mkdir(parents=True, exist_ok=True)
    exports: dict[str, Path] = {}
    with RpfmWsSession(server, home=home, library_path=library_path) as session:
        game = session.call({"SetGameSelected": [GAME_KEY, False]})
        opened = session.call({"OpenPackFiles": [str(output.resolve())]})
        try:
            pack_key = opened["StringContainerInfo"][0]
        except (KeyError, IndexError, TypeError) as error:
            raise BuildError(f"RPFM could not reopen final pack: {opened!r}") from error
        tree = session.call({"GetPackFileDataForTreeView": pack_key})
        try:
            tree_paths = sorted(
                item["path"] for item in tree["ContainerInfoVecRFileInfo"][1]
            )
        except (KeyError, IndexError, TypeError) as error:
            raise BuildError(f"invalid RPFM tree response: {tree!r}") from error
        if tree_paths != sorted(REQUIRED_PACK_PATHS):
            raise BuildError(f"RPFM reopened a different path set: {tree_paths}")
        for filename, _, _, internal_path in DB_SPECS:
            destination = export_root / f"{filename}.tsv"
            response = session.call(
                {"ExportTSV": [pack_key, internal_path, str(destination.resolve()), "PackFile"]}
            )
            if response != "Success":
                raise BuildError(f"RPFM failed to export {internal_path}: {response!r}")
            exports[filename] = destination
        destination = export_root / "wr2_world_resistance.loc.tsv"
        response = session.call(
            {"ExportTSV": [pack_key, LOC_PATH, str(destination.resolve()), "PackFile"]}
        )
        if response != "Success":
            raise BuildError(f"RPFM failed to export {LOC_PATH}: {response!r}")
        exports["localisation"] = destination
        diagnostics = session.call({"DiagnosticsCheck": [[], False]})

    expected_rows = _rows_by_name(expected_tsvs)
    exported_rows = _rows_by_name(exports)
    if exported_rows != expected_rows:
        mismatched = [name for name in expected_rows if expected_rows[name] != exported_rows[name]]
        raise BuildError(f"RPFM DB/Loc round-trip changed rows in: {mismatched}")
    # Re-apply the strongest fame validator to the RPFM-exported table.
    validate_fame(exports["fame_levels"])

    report_types = sorted(set(_collect_report_types(diagnostics)))
    allowed_environment_only = {"IncorrectGamePath"}
    unexpected = sorted(set(report_types).difference(allowed_environment_only))
    if unexpected:
        raise BuildError(f"RPFM diagnostics reported structural problems: {unexpected}")
    return {
        "game_selection": game,
        "container": {
            "pfh_version": opened["StringContainerInfo"][1].get("pfh_version"),
            "pfh_file_type": opened["StringContainerInfo"][1].get("pfh_file_type"),
            "bitmask": opened["StringContainerInfo"][1].get("bitmask"),
            "compress": opened["StringContainerInfo"][1].get("compress"),
        },
        "tree_paths": tree_paths,
        "exports": {name: path.name for name, path in exports.items()},
        "diagnostics": diagnostics,
        "diagnostic_report_types": report_types,
        "environment_only_diagnostics": sorted(
            set(report_types).intersection(allowed_environment_only)
        ),
        "unexpected_diagnostics": unexpected,
    }


def build(arguments: argparse.Namespace) -> dict[str, object]:
    project = arguments.project.resolve()
    output = arguments.output.resolve()
    report_path = arguments.report.resolve()
    server = arguments.rpfm_server.resolve()
    source_home = arguments.rpfm_home.resolve()
    schema_source = (
        arguments.schema.resolve()
        if arguments.schema
        else source_home / ".config" / "rpfm" / "schemas" / "schema_rom2.ron"
    )
    matrix = validate_matrix(project)
    fame_rows = validate_fame(project / "db_src" / "fame_levels.tsv")
    tsv_paths = generate_effect_tsvs(project, matrix)
    # Validate generated inputs independently before RPFM sees them.
    bundle_header, bundle_metadata, bundle_rows = _parse_tsv(tsv_paths["effect_bundles"])
    junction_header, junction_metadata, junction_rows = _parse_tsv(
        tsv_paths["effect_bundles_to_effects"]
    )
    _, _, message_event_rows = _parse_tsv(tsv_paths["message_events"])
    _, _, message_string_rows = _parse_tsv(tsv_paths["message_event_strings"])
    _, _, localisation_rows = _parse_tsv(tsv_paths["localisation"])
    if bundle_header != EFFECT_BUNDLE_HEADER or len(bundle_rows) != 9:
        raise BuildError("generated effect_bundles table failed validation")
    if bundle_metadata != "#effect_bundles_tables;1;db/effect_bundles_tables/wr2_world_resistance":
        raise BuildError("generated effect_bundles metadata failed validation")
    if junction_header != JUNCTION_HEADER or len(junction_rows) != 162:
        raise BuildError("generated bundle junction table failed validation")
    if junction_metadata != (
        "#effect_bundles_to_effects_junctions_tables;2;"
        "db/effect_bundles_to_effects_junctions_tables/wr2_world_resistance"
    ):
        raise BuildError("generated bundle junction metadata failed validation")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="wr2-build-") as temporary_name:
        temporary = Path(temporary_name)
        encode_home = temporary / "rpfm-encode-home"
        reopen_home = temporary / "rpfm-reopen-home"
        _copy_schema(schema_source, encode_home)
        _copy_schema(schema_source, reopen_home)
        stage_pack = temporary / "rpfm-stage.pack"
        encode = _rpfm_encode(
            server,
            encode_home,
            arguments.rpfm_library_path,
            tsv_paths,
            stage_pack,
        )
        candidate = temporary / "wr2_world_resistance.pack"
        final_validation = _normalize_rpfm_stage(stage_pack, candidate, project)
        reopen = _rpfm_reopen_validate(
            server,
            reopen_home,
            arguments.rpfm_library_path,
            candidate,
            tsv_paths,
            project / "validation" / "rpfm_roundtrip",
        )
        _atomic_copy(candidate, output)
        if arguments.keep_stage:
            kept = arguments.keep_stage.resolve()
            kept.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(stage_pack, kept)

    result = {
        "build_tool_version": BUILD_TOOL_VERSION,
        "release_version": RELEASE_VERSION,
        "target": {
            "game": GAME_KEY,
            "campaign": CAMPAIGN_KEY,
            "compatibility": "current stable pre-PANTHEON",
            "fame_table_version": 4,
        },
        "inputs": {
            "schema_sha256": _sha256(schema_source),
            "matrix_json_sha256": _sha256(project / "config" / "bundle_matrix.json"),
            "matrix_csv_sha256": _sha256(project / "config" / "bundle_matrix.csv"),
            "fame_tsv_sha256": _sha256(project / "db_src" / "fame_levels.tsv"),
            "message_events_tsv_sha256": _sha256(tsv_paths["message_events"]),
            "message_event_strings_tsv_sha256": _sha256(
                tsv_paths["message_event_strings"]
            ),
            "localisation_tsv_sha256": _sha256(tsv_paths["localisation"]),
            "lua_sha256": {
                path: _sha256(project / "pack_root" / path) for path in LUA_PATHS
            },
        },
        "validated_contract": {
            "effect_count": len(matrix["effects"]),
            "effect_bundle_rows": len(bundle_rows),
            "bundle_effect_rows": len(junction_rows),
            "zero_effect_rows": 0,
            "fame_rows": len(fame_rows),
            "unique_fame_keys": len({(row[0], row[1]) for row in fame_rows}),
            "message_event_rows": len(message_event_rows),
            "message_event_string_rows": len(message_string_rows),
            "localisation_rows": len(localisation_rows),
            "custom_event_keys": STATUS_EVENT_KEYS,
            "message_event_cultures": STATUS_CULTURES,
            "ai_prestige_thresholds": [int(row[2]) for row in fame_rows],
            "human_player_prestige_thresholds": [int(row[7]) for row in fame_rows],
            "army_caps": [int(row[3]) for row in fame_rows],
        },
        "rpfm_encode": encode,
        "final_pack": final_validation,
        "rpfm_reopen": reopen,
    }
    _atomic_write_text(report_path, json.dumps(result, indent=2, sort_keys=True) + "\n")
    return result


def _default_server() -> Path:
    configured = os.environ.get("RPFM_SERVER")
    if configured:
        return Path(configured)
    return Path("/tmp/rpfm-v5.0.5/usr/bin/rpfm_server")


def _default_home() -> Path:
    configured = os.environ.get("RPFM_HOME")
    if configured:
        return Path(configured)
    return Path("/tmp/rpfm-home")


def _build_parser() -> argparse.ArgumentParser:
    project = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=project)
    parser.add_argument("--rpfm-server", type=Path, default=_default_server())
    parser.add_argument("--rpfm-home", type=Path, default=_default_home())
    parser.add_argument("--schema", type=Path, help="override schema_rom2.ron source")
    parser.add_argument(
        "--rpfm-library-path",
        default=os.environ.get(
            "RPFM_LIBRARY_PATH",
            "/tmp/libgit2/usr/lib:/tmp/llhttp/usr/lib:/tmp/libssh2/usr/lib",
        ),
        help="LD_LIBRARY_PATH required by the RPFM server build",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=project / "dist" / "wr2_world_resistance.pack",
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=project / "validation" / "build_report.json",
    )
    parser.add_argument(
        "--keep-stage",
        type=Path,
        help="optional path at which to retain RPFM's metadata-bearing staging pack",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    arguments = parser.parse_args(argv)
    try:
        report = build(arguments)
    except (
        BuildError,
        RpfmWsError,
        PackFormatError,
        OSError,
        ValueError,
        json.JSONDecodeError,
    ) as error:
        print(f"build failed: {error}", file=sys.stderr)
        return 2
    final = report["final_pack"]
    print(
        f"built {arguments.output.resolve()} ({final['file_count']} files, "
        f"sha256 {final['sha256']})"
    )
    print(f"validation report: {arguments.report.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
