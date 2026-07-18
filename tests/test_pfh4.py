from __future__ import annotations

import struct
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from tools.pfh4 import (
    HEADER,
    MOD_FILE_TYPE,
    PFH4_MAGIC,
    PackFormatError,
    collect_directory,
    read_pack,
    validate_pack,
    write_pack,
    write_pack_file,
)


class Pfh4RoundTripTests(unittest.TestCase):
    def test_round_trip_opaque_payloads(self) -> None:
        original = {
            "script/campaign/main_rome/scripting.lua": b"print('ok')\n",
            "binary/all-bytes.bin": bytes(range(256)),
            "empty.dat": b"",
        }

        encoded = write_pack(original)
        decoded = read_pack(encoded)

        self.assertEqual(decoded.as_dict(), {
            "binary/all-bytes.bin": bytes(range(256)),
            "empty.dat": b"",
            "script/campaign/main_rome/scripting.lua": b"print('ok')\n",
        })

    def test_header_is_mod_three_with_no_flags_or_dependencies(self) -> None:
        encoded = write_pack({"a.txt": b"a"})
        (
            magic,
            type_and_flags,
            dependency_count,
            dependency_index_size,
            file_count,
            _file_index_size,
            timestamp,
        ) = HEADER.unpack_from(encoded)

        self.assertEqual(magic, PFH4_MAGIC)
        self.assertEqual(type_and_flags, MOD_FILE_TYPE)
        self.assertEqual(dependency_count, 0)
        self.assertEqual(dependency_index_size, 0)
        self.assertEqual(file_count, 1)
        self.assertEqual(timestamp, 0)

    def test_minimal_pack_matches_pfh4_layout(self) -> None:
        expected = (
            b"PFH4"
            + struct.pack("<I", 3)  # Mod type, no flags
            + struct.pack("<I", 0)  # dependency count
            + struct.pack("<I", 0)  # dependency index size
            + struct.pack("<I", 1)  # file count
            + struct.pack("<I", 6)  # u32 size + "a" + NUL
            + struct.pack("<I", 0)  # deterministic timestamp
            + struct.pack("<I", 1)
            + b"a\x00"
            + b"x"
        )
        self.assertEqual(write_pack({"a": b"x"}), expected)

    def test_paths_are_sorted_case_insensitively_and_stored_with_backslashes(self) -> None:
        encoded = write_pack([
            ("Zeta/file", b"z"),
            ("alpha/file", b"a"),
            ("Beta/file", b"b"),
        ])
        archive = read_pack(encoded)
        self.assertEqual(
            [entry.path for entry in archive.entries],
            ["alpha/file", "Beta/file", "Zeta/file"],
        )

        file_index_size = archive.header.file_index_size
        raw_index = encoded[HEADER.size:HEADER.size + file_index_size]
        self.assertIn(b"alpha\\file\x00", raw_index)
        self.assertNotIn(b"alpha/file\x00", raw_index)

    def test_output_is_deterministic_across_input_order(self) -> None:
        first = write_pack([("c", b"3"), ("a", b"1"), ("b", b"2")])
        second = write_pack([("b", b"2"), ("c", b"3"), ("a", b"1")])
        self.assertEqual(first, second)
        self.assertEqual(validate_pack(first)["sha256"], validate_pack(second)["sha256"])

    def test_atomic_file_writer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "dist" / "example.pack"
            write_pack_file(output, {"a": b"first"})
            write_pack_file(output, {"a": b"second"})
            self.assertEqual(read_pack(output.read_bytes()).as_dict(), {"a": b"second"})


class Pfh4SafetyTests(unittest.TestCase):
    def test_rejects_unsafe_paths(self) -> None:
        for path in ("", "/absolute", "C:/drive", "../up", "a/../b", "a//b", "./a", "a/"):
            with self.subTest(path=path), self.assertRaises(PackFormatError):
                write_pack({path: b"x"})

    def test_rejects_case_insensitive_duplicates(self) -> None:
        with self.assertRaises(PackFormatError):
            write_pack([("Script/A.lua", b"1"), ("script/a.lua", b"2")])

    def test_rejects_truncation_and_trailing_bytes(self) -> None:
        encoded = write_pack({"a": b"payload"})
        with self.assertRaises(PackFormatError):
            read_pack(encoded[:-1])
        with self.assertRaises(PackFormatError):
            read_pack(encoded + b"junk")

    def test_rejects_flags_dependencies_type_and_timestamp(self) -> None:
        encoded = bytearray(write_pack({"a": b"x"}))
        mutations = {
            "flags": (4, MOD_FILE_TYPE | 0x40),
            "file type": (4, 4),
            "dependencies": (8, 1),
            "timestamp": (24, 1),
        }
        for label, (offset, value) in mutations.items():
            mutated = bytearray(encoded)
            struct.pack_into("<I", mutated, offset, value)
            with self.subTest(label=label), self.assertRaises(PackFormatError):
                read_pack(mutated)

    def test_rejects_unsorted_index(self) -> None:
        encoded = write_pack({"a": b"1", "b": b"2"})
        # Both paths are one byte, so swapping their index records preserves the
        # declared index size. Payload order is irrelevant: index ordering alone
        # must be rejected.
        index_start = HEADER.size
        record_size = 4 + 1 + 1
        first = encoded[index_start:index_start + record_size]
        second = encoded[index_start + record_size:index_start + 2 * record_size]
        mutated = (
            encoded[:index_start]
            + second
            + first
            + encoded[index_start + 2 * record_size:]
        )
        with self.assertRaises(PackFormatError):
            read_pack(mutated)

    def test_collect_directory_rejects_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "real.txt").write_bytes(b"real")
            link = root / "link.txt"
            try:
                link.symlink_to(root / "real.txt")
            except (OSError, NotImplementedError):
                self.skipTest("symlinks unavailable on this platform")
            with self.assertRaises(PackFormatError):
                collect_directory(root)


if __name__ == "__main__":
    unittest.main()
