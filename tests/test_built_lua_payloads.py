from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "dist" / "@wr2_world_resistance.pack"
LUA_PATHS = (
    "lua_scripts/all_scripted.lua",
    "script/campaign/wr2/wr2_world_resistance.lua",
)
LUA_INTEGRATION_TESTS = (
    "test_loader_registry_handoff.lua",
    "test_listener_setup_recovery.lua",
    "test_loader_setup_failure.lua",
)


class BuiltLuaPayloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        from tools.pfh4 import read_pack

        cls.pack_files = read_pack(PACK.read_bytes()).as_dict()

    def test_shipped_lua_is_byte_identical_to_tested_source(self) -> None:
        for relative in LUA_PATHS:
            with self.subTest(path=relative):
                self.assertIn(relative, self.pack_files)
                self.assertEqual(
                    self.pack_files[relative],
                    (ROOT / "pack_root" / relative).read_bytes(),
                )

    def test_registry_integration_fixtures_against_extracted_pack(self) -> None:
        texlua = shutil.which("texlua")
        if texlua is None:
            self.skipTest("texlua is unavailable")

        with tempfile.TemporaryDirectory() as temporary:
            extracted_root = Path(temporary) / "pack_root"
            for relative in LUA_PATHS:
                destination = extracted_root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(self.pack_files[relative])

            environment = os.environ.copy()
            environment["WR2_PACK_ROOT"] = str(extracted_root)
            for filename in LUA_INTEGRATION_TESTS:
                with self.subTest(test=filename):
                    completed = subprocess.run(
                        [texlua, str(ROOT / "tests" / filename)],
                        cwd=extracted_root,
                        env=environment,
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        timeout=30,
                        check=False,
                    )
                    self.assertEqual(
                        completed.returncode,
                        0,
                        f"{filename} failed against extracted pack:\n{completed.stdout}",
                    )
                    self.assertIn("assertions passed", completed.stdout)


if __name__ == "__main__":
    unittest.main()
