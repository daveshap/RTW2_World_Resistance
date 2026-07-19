#!/usr/bin/env python3
"""Build the Lua-only World Resistance 0.1.6 hotfix from the verified v0.1.1 pack.

The 0.1.6 release keeps the verified DB/Loc payloads while correcting field-
army telemetry, adding region-proportional mobilization goals, strengthening
AI-only strategic cooperation, and bounding local diagnostic logs.
Its five RPFM-encoded DB tables and Loc payload are copied byte-for-byte from
the v0.1.1 pack that was already encoded, reopened, exported, and compared
with source under RPFM 5.0.5. This builder refuses to run unless the complete
base pack, prior report, source inputs, internal path set, and unchanged
payload bytes match the recorded release contract.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Sequence

try:
    from .build_pack import (
        CAMPAIGN_KEY,
        GAME_KEY,
        LUA_PATHS,
        REQUIRED_PACK_PATHS,
        _sha256,
        _atomic_write_text,
        generate_effect_tsvs,
        validate_fame,
        validate_matrix,
    )
    from .pfh4 import PackFormatError, read_pack, validate_pack, write_pack_file
except ImportError:
    from build_pack import (
        CAMPAIGN_KEY,
        GAME_KEY,
        LUA_PATHS,
        REQUIRED_PACK_PATHS,
        _sha256,
        _atomic_write_text,
        generate_effect_tsvs,
        validate_fame,
        validate_matrix,
    )
    from pfh4 import PackFormatError, read_pack, validate_pack, write_pack_file


BUILD_TOOL_VERSION = "1.6.0-hotfix"
RELEASE_VERSION = "0.1.6-beta"
BASE_RELEASE_VERSION = "0.1.1-beta"
BASE_PACK_SHA256 = "9ca3cf59de7d1851110994917b43a777b46f5adf05c7b61e274439669fbada4e"
DIRECTOR_VERSION = 8
TELEMETRY_SCHEMA = 1
PACK_FILENAME = "@wr2_world_resistance.pack"
BOOTSTRAP_LOG_PATH = "wr2_world_resistance_bootstrap.log"
DIAGNOSTIC_LOG_PATH = "data/wr2_world_resistance.log"
BASE_DIRECTOR_PATH = "lua_scripts/wr2_world_resistance.lua"
FINAL_DIRECTOR_PATH = "script/campaign/wr2/wr2_world_resistance.lua"
BASE_REQUIRED_PACK_PATHS = sorted(
    [path for path in REQUIRED_PACK_PATHS if path != FINAL_DIRECTOR_PATH]
    + [BASE_DIRECTOR_PATH],
    key=str.casefold,
)


class HotfixBuildError(RuntimeError):
    """Raised when the verified-base hotfix contract is violated."""


def _sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _assert_source_hashes(project: Path, prior: dict[str, object]) -> dict[str, object]:
    # This regenerates and validates the two effect TSVs and validates the
    # unchanged message/Loc inputs without invoking RPFM.
    matrix = validate_matrix(project)
    validate_fame(project / "db_src" / "fame_levels.tsv")
    generated = generate_effect_tsvs(project, matrix)

    previous_inputs = prior["inputs"]
    current_inputs = {
        "schema_sha256": previous_inputs["schema_sha256"],
        "matrix_json_sha256": _sha256(project / "config" / "bundle_matrix.json"),
        "matrix_csv_sha256": _sha256(project / "config" / "bundle_matrix.csv"),
        "fame_tsv_sha256": _sha256(project / "db_src" / "fame_levels.tsv"),
        "message_events_tsv_sha256": _sha256(generated["message_events"]),
        "message_event_strings_tsv_sha256": _sha256(
            generated["message_event_strings"]
        ),
        "localisation_tsv_sha256": _sha256(generated["localisation"]),
        "lua_sha256": {
            path: _sha256(project / "pack_root" / path) for path in LUA_PATHS
        },
    }

    for key, value in current_inputs.items():
        if key in {"lua_sha256", "schema_sha256"}:
            continue
        if value != previous_inputs[key]:
            raise HotfixBuildError(
                f"Lua-only hotfix changed verified source input {key}: {value}"
            )
    return current_inputs


def build(
    project: Path,
    base_pack_path: Path,
    prior_report_path: Path,
    output_path: Path,
    report_path: Path,
) -> dict[str, object]:
    base_payload = base_pack_path.read_bytes()
    if _sha256_bytes(base_payload) != BASE_PACK_SHA256:
        raise HotfixBuildError("verified v0.1.1 base pack hash mismatch")

    prior = json.loads(prior_report_path.read_text(encoding="utf-8"))
    if prior.get("release_version") != BASE_RELEASE_VERSION:
        raise HotfixBuildError("prior report release mismatch")
    if prior.get("final_pack", {}).get("sha256") != BASE_PACK_SHA256:
        raise HotfixBuildError("prior report does not describe the verified base pack")

    archive = read_pack(base_payload)
    base_files = archive.as_dict()
    if sorted(base_files, key=str.casefold) != BASE_REQUIRED_PACK_PATHS:
        raise HotfixBuildError("verified base pack internal path set mismatch")

    current_inputs = _assert_source_hashes(project, prior)
    final_files = dict(base_files)
    final_files.pop(BASE_DIRECTOR_PATH)
    for path in LUA_PATHS:
        final_files[path] = (project / "pack_root" / path).read_bytes()

    modified_paths = ["lua_scripts/all_scripted.lua"]
    added_paths = [FINAL_DIRECTOR_PATH]
    removed_paths = [BASE_DIRECTOR_PATH]
    if final_files[modified_paths[0]] == base_files[modified_paths[0]]:
        raise HotfixBuildError("hotfix loader payload did not change")
    if FINAL_DIRECTOR_PATH not in final_files or BASE_DIRECTOR_PATH in final_files:
        raise HotfixBuildError("director relocation contract failed")

    unchanged_paths = sorted(path for path in final_files if path not in LUA_PATHS)
    base_unchanged_paths = sorted(
        (
            path
            for path in base_files
            if path not in {"lua_scripts/all_scripted.lua", BASE_DIRECTOR_PATH}
        ),
        key=str.casefold,
    )
    if sorted(unchanged_paths, key=str.casefold) != base_unchanged_paths:
        raise HotfixBuildError("non-Lua path set changed during hotfix")
    for path in unchanged_paths:
        if final_files[path] != base_files[path]:
            raise HotfixBuildError(f"verified non-Lua payload changed: {path}")

    write_pack_file(output_path, final_files)
    output_payload = output_path.read_bytes()
    final_validation = validate_pack(output_payload)
    if final_validation["paths"] != REQUIRED_PACK_PATHS:
        raise HotfixBuildError("final deterministic pack path order mismatch")

    reopen = copy.deepcopy(prior["rpfm_reopen"])
    reopen["base_rpfm_tree_paths"] = reopen.pop("tree_paths")
    reopen["final_tree_paths"] = final_validation["paths"]
    reopen["validation_scope"] = (
        "Inherited for six byte-identical RPFM-verified DB/Loc payloads; "
        "the new PFH4 container was independently reopened by tools/pfh4.py."
    )
    reopen["rpfm_revalidated_this_hotfix"] = False

    encode = copy.deepcopy(prior["rpfm_encode"])
    encode["validation_scope"] = (
        "Inherited for six byte-identical DB/Loc payloads from 0.1.1-beta."
    )
    encode["rpfm_reencoded_this_hotfix"] = False

    result = {
        "build_tool_version": BUILD_TOOL_VERSION,
        "release_version": RELEASE_VERSION,
        "target": {
            "game": GAME_KEY,
            "campaign": CAMPAIGN_KEY,
            "compatibility": "current stable pre-PANTHEON",
            "fame_table_version": 4,
        },
        "runtime_contract": {
            "pack_filename": PACK_FILENAME,
            "director_version": DIRECTOR_VERSION,
            "telemetry_schema": TELEMETRY_SCHEMA,
            "bootstrap_log_path": BOOTSTRAP_LOG_PATH,
            "diagnostic_log_path": DIAGNOSTIC_LOG_PATH,
            "diagnostic_log_max_lines": 1000,
            "diagnostic_log_keep_lines": 800,
            "director_module_path": FINAL_DIRECTOR_PATH,
            "director_require_name": "wr2_world_resistance",
            "listener_registration": "explicit_loader_setup_with_exported_registry",
            "listener_idempotence": "registry_and_callback_identity",
            "listener_partial_retry": "attached_callback_or_repeated_setup",
            "interface_binding": "lazy_existing_episodic_state",
            "campaign_detection": "campaign_name_predicate_main_rome",
            "initialization_event": "FirstTickAfterWorldCreated",
            "initialization_retry": "first_FactionTurnStart_each_campaign_turn",
            "world_diagnostics": "reasoned_bootstrap_state_and_sink_status",
            "army_measurement": "general_led_land_forces_only",
            "ai_army_goal": "min_four_per_region_human_parity_sixteen",
            "ai_cooperation": "pair_scoped_best_friends_lock_at_tier_85",
            "visible_attitude_mutation": "read_only_telemetry_no_unsafe_global_bonus",
        },
        "inputs": current_inputs,
        "validated_contract": prior["validated_contract"],
        "payload_provenance": {
            "mode": "lua_only_hotfix_from_rpfm_verified_base",
            "base_release": BASE_RELEASE_VERSION,
            "base_pack_sha256": BASE_PACK_SHA256,
            "prior_report": prior_report_path.relative_to(project).as_posix(),
            "modified_paths": modified_paths,
            "added_paths": added_paths,
            "removed_paths": removed_paths,
            "unchanged_payload_sha256": {
                path: _sha256_bytes(final_files[path]) for path in unchanged_paths
            },
            "rpfm_revalidated_this_hotfix": False,
        },
        "rpfm_encode": encode,
        "final_pack": final_validation,
        "rpfm_reopen": reopen,
    }
    _atomic_write_text(report_path, json.dumps(result, indent=2, sort_keys=True) + "\n")
    return result


def _parser() -> argparse.ArgumentParser:
    project = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=project)
    parser.add_argument(
        "--base-pack",
        type=Path,
        default=project / "validation" / "wr2_world_resistance_v0.1.1-beta.pfh4",
    )
    parser.add_argument(
        "--prior-report",
        type=Path,
        default=project / "validation" / "build_report_v0.1.1.json",
    )
    parser.add_argument(
        "--output", type=Path, default=project / "dist" / PACK_FILENAME
    )
    parser.add_argument(
        "--report", type=Path, default=project / "validation" / "build_report.json"
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        result = build(
            args.project.resolve(),
            args.base_pack.resolve(),
            args.prior_report.resolve(),
            args.output.resolve(),
            args.report.resolve(),
        )
    except (HotfixBuildError, PackFormatError, OSError, ValueError, KeyError) as error:
        print(f"hotfix build failed: {error}")
        return 2
    final = result["final_pack"]
    print(
        f"built {args.output.resolve()} ({final['file_count']} files, "
        f"sha256 {final['sha256']})"
    )
    print(f"validation report: {args.report.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
