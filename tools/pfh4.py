#!/usr/bin/env python3
"""Small, deterministic reader/writer for Rome II's safe PFH4 Mod subset.

This module deliberately implements less than the complete PFH4 format. Packs
written here always have:

* a ``PFH4`` preamble;
* file type ``Mod`` (numeric value 3);
* no PFH flags, dependencies, compression, encryption, or per-file timestamps;
* a zero header timestamp; and
* a case-insensitively sorted file index using backslash-separated paths.

Payloads are opaque bytes. In particular, this module does not encode or
validate Total War DB tables.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable, Mapping, Sequence


PFH4_MAGIC = b"PFH4"
MOD_FILE_TYPE = 3
FILE_TYPE_MASK = 0x0F
HEADER = struct.Struct("<4sIIIIII")
U32 = struct.Struct("<I")
MAX_U32 = (1 << 32) - 1
DEFAULT_MAX_FILES = 1_000_000
MAX_INTERNAL_PATH_BYTES = 4096


class PackFormatError(ValueError):
    """Raised when a pack is unsafe, unsupported, or structurally invalid."""


@dataclass(frozen=True)
class PackEntry:
    """One file in a pack, using a canonical forward-slash internal path."""

    path: str
    data: bytes


@dataclass(frozen=True)
class PackHeader:
    """Decoded PFH4 header fields."""

    file_type: int
    flags: int
    dependency_count: int
    dependency_index_size: int
    file_count: int
    file_index_size: int
    timestamp: int


@dataclass(frozen=True)
class PackArchive:
    """A validated deterministic PFH4 archive."""

    header: PackHeader
    entries: tuple[PackEntry, ...]

    def as_dict(self) -> dict[str, bytes]:
        """Return entries as a new insertion-ordered dictionary."""

        return {entry.path: entry.data for entry in self.entries}


def _as_bytes(data: object, path: str) -> bytes:
    if isinstance(data, bytes):
        return data
    if isinstance(data, (bytearray, memoryview)):
        return bytes(data)
    raise TypeError(f"payload for {path!r} must be bytes-like, not {type(data).__name__}")


def canonical_internal_path(path: str) -> str:
    """Validate and canonicalise a path for storage inside a pack.

    Absolute paths, drive-qualified paths, traversal, empty components, NULs,
    and dot components are rejected. Both slash styles are accepted as input.
    """

    if not isinstance(path, str):
        raise TypeError("internal path must be a string")
    if not path:
        raise PackFormatError("internal path must not be empty")
    if "\x00" in path:
        raise PackFormatError(f"internal path contains NUL: {path!r}")

    path = path.replace("\\", "/")
    if path.startswith("/"):
        raise PackFormatError(f"absolute internal path is forbidden: {path!r}")
    if len(path) >= 2 and path[1] == ":" and path[0].isalpha():
        raise PackFormatError(f"drive-qualified internal path is forbidden: {path!r}")

    parts = path.split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise PackFormatError(f"unsafe internal path component in {path!r}")

    canonical = PurePosixPath(*parts).as_posix()
    encoded = canonical.encode("utf-8")
    if len(encoded) > MAX_INTERNAL_PATH_BYTES:
        raise PackFormatError(
            f"internal path exceeds {MAX_INTERNAL_PATH_BYTES} UTF-8 bytes: {canonical!r}"
        )
    return canonical


def _stored_path(canonical_path: str) -> str:
    return canonical_path.replace("/", "\\")


def _sort_key(entry: PackEntry) -> tuple[str, str]:
    # RPFM sorts PFH4 paths by a lowercased backslash path. The second key makes
    # our output deterministic even though case-only duplicates are rejected.
    stored = _stored_path(entry.path)
    return (stored.lower(), stored)


def _normalise_entries(
    files: Mapping[str, object] | Iterable[tuple[str, object] | PackEntry],
) -> list[PackEntry]:
    source: Iterable[tuple[str, object] | PackEntry]
    source = files.items() if isinstance(files, Mapping) else files

    entries: list[PackEntry] = []
    seen: dict[str, str] = {}
    for item in source:
        if isinstance(item, PackEntry):
            raw_path, raw_data = item.path, item.data
        else:
            try:
                raw_path, raw_data = item
            except (TypeError, ValueError) as error:
                raise TypeError("entries must be PackEntry objects or (path, data) pairs") from error

        path = canonical_internal_path(raw_path)
        folded = path.casefold()
        if folded in seen:
            raise PackFormatError(
                f"case-insensitive duplicate internal paths: {seen[folded]!r} and {path!r}"
            )
        seen[folded] = path
        data = _as_bytes(raw_data, path)
        if len(data) > MAX_U32:
            raise PackFormatError(f"file is too large for PFH4's u32 size: {path!r}")
        entries.append(PackEntry(path, data))

    if len(entries) > MAX_U32:
        raise PackFormatError("too many files for PFH4's u32 count")
    entries.sort(key=_sort_key)
    return entries


def write_pack(
    files: Mapping[str, object] | Iterable[tuple[str, object] | PackEntry],
) -> bytes:
    """Encode opaque files as a deterministic, dependency-free PFH4 Mod pack."""

    entries = _normalise_entries(files)
    index_parts: list[bytes] = []
    data_parts: list[bytes] = []

    for entry in entries:
        stored_path = _stored_path(entry.path).encode("utf-8")
        index_parts.append(U32.pack(len(entry.data)) + stored_path + b"\x00")
        data_parts.append(entry.data)

    file_index = b"".join(index_parts)
    if len(file_index) > MAX_U32:
        raise PackFormatError("file index is too large for PFH4's u32 size")

    header = HEADER.pack(
        PFH4_MAGIC,
        MOD_FILE_TYPE,
        0,  # dependency count
        0,  # dependency index size
        len(entries),
        len(file_index),
        0,  # deterministic internal timestamp
    )
    return b"".join((header, file_index, *data_parts))


def write_pack_file(
    destination: os.PathLike[str] | str,
    files: Mapping[str, object] | Iterable[tuple[str, object] | PackEntry],
) -> Path:
    """Atomically write a deterministic PFH4 pack and return its path."""

    destination = Path(destination)
    if destination.exists() and destination.is_dir():
        raise IsADirectoryError(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    data = write_pack(files)

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, destination)
    except BaseException:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise
    return destination


def _read_u32(data: bytes, offset: int, limit: int, label: str) -> tuple[int, int]:
    end = offset + U32.size
    if end > limit:
        raise PackFormatError(f"truncated {label}")
    return U32.unpack_from(data, offset)[0], end


def _read_index_path(data: bytes, offset: int, index_end: int) -> tuple[str, int]:
    terminator = data.find(b"\x00", offset, index_end)
    if terminator < 0:
        raise PackFormatError("file-index path is not NUL-terminated inside the declared index")
    encoded = data[offset:terminator]
    try:
        stored = encoded.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PackFormatError("file-index path is not valid UTF-8") from error
    if not stored:
        raise PackFormatError("file-index path must not be empty")
    if "/" in stored:
        raise PackFormatError(f"PFH4 path is not backslash-canonical: {stored!r}")

    canonical = canonical_internal_path(stored)
    if _stored_path(canonical) != stored:
        raise PackFormatError(f"PFH4 path is not canonical: {stored!r}")
    return canonical, terminator + 1


def read_pack(
    data: bytes | bytearray | memoryview,
    *,
    max_files: int = DEFAULT_MAX_FILES,
) -> PackArchive:
    """Read and strictly validate the deterministic PFH4 subset this tool writes.

    General PFH4 packs using dependencies, flags, nonzero timestamps, or a type
    other than Mod are intentionally rejected instead of being partially parsed.
    """

    blob = bytes(data)
    if len(blob) < HEADER.size:
        raise PackFormatError(f"truncated PFH4 header: need {HEADER.size} bytes")

    (
        magic,
        type_and_flags,
        dependency_count,
        dependency_index_size,
        file_count,
        file_index_size,
        timestamp,
    ) = HEADER.unpack_from(blob)

    if magic != PFH4_MAGIC:
        raise PackFormatError(f"unsupported or invalid pack preamble: {magic!r}")
    file_type = type_and_flags & FILE_TYPE_MASK
    flags = type_and_flags & ~FILE_TYPE_MASK
    if file_type != MOD_FILE_TYPE:
        raise PackFormatError(f"expected PFH4 Mod file type 3, found {file_type}")
    if flags != 0:
        raise PackFormatError(f"PFH4 flags are outside the supported safe subset: 0x{flags:08x}")
    if dependency_count != 0 or dependency_index_size != 0:
        raise PackFormatError("PFH4 dependencies are outside the supported safe subset")
    if timestamp != 0:
        raise PackFormatError("nonzero PFH4 timestamp is outside the deterministic subset")
    if max_files < 0:
        raise ValueError("max_files must not be negative")
    if file_count > max_files:
        raise PackFormatError(f"file count {file_count} exceeds safety limit {max_files}")

    index_start = HEADER.size
    index_end = index_start + file_index_size
    if index_end > len(blob):
        raise PackFormatError("declared file index extends beyond end of pack")

    metadata: list[tuple[str, int]] = []
    seen: dict[str, str] = {}
    offset = index_start
    for number in range(file_count):
        size, offset = _read_u32(blob, offset, index_end, f"size for file-index entry {number}")
        path, offset = _read_index_path(blob, offset, index_end)
        folded = path.casefold()
        if folded in seen:
            raise PackFormatError(
                f"case-insensitive duplicate internal paths: {seen[folded]!r} and {path!r}"
            )
        seen[folded] = path
        metadata.append((path, size))

    if offset != index_end:
        raise PackFormatError(
            f"file-index size mismatch: parsed {offset - index_start}, declared {file_index_size}"
        )

    paths_only = [path for path, _ in metadata]
    expected_order = sorted(paths_only, key=lambda path: (_stored_path(path).lower(), _stored_path(path)))
    if paths_only != expected_order:
        raise PackFormatError("file index is not in deterministic case-insensitive path order")

    entries: list[PackEntry] = []
    data_offset = index_end
    for path, size in metadata:
        data_end = data_offset + size
        if data_end > len(blob):
            raise PackFormatError(f"payload for {path!r} extends beyond end of pack")
        entries.append(PackEntry(path, blob[data_offset:data_end]))
        data_offset = data_end

    if data_offset != len(blob):
        raise PackFormatError(f"pack has {len(blob) - data_offset} unexplained trailing bytes")

    header = PackHeader(
        file_type=file_type,
        flags=flags,
        dependency_count=dependency_count,
        dependency_index_size=dependency_index_size,
        file_count=file_count,
        file_index_size=file_index_size,
        timestamp=timestamp,
    )
    return PackArchive(header=header, entries=tuple(entries))


def validate_pack(data: bytes | bytearray | memoryview) -> dict[str, object]:
    """Return a machine-readable report for a valid deterministic pack.

    Invalid input raises :class:`PackFormatError`.
    """

    blob = bytes(data)
    archive = read_pack(blob)
    return {
        "valid": True,
        "format": "PFH4",
        "file_type": archive.header.file_type,
        "flags": archive.header.flags,
        "dependency_count": archive.header.dependency_count,
        "timestamp": archive.header.timestamp,
        "file_count": archive.header.file_count,
        "file_index_size": archive.header.file_index_size,
        "pack_size": len(blob),
        "sha256": hashlib.sha256(blob).hexdigest(),
        "paths": [entry.path for entry in archive.entries],
    }


def collect_directory(root: os.PathLike[str] | str) -> list[PackEntry]:
    """Read regular, non-symlink files below ``root`` as opaque pack entries."""

    root = Path(root)
    if not root.is_dir():
        raise NotADirectoryError(root)
    root = root.resolve()
    entries: list[PackEntry] = []

    for filesystem_path in sorted(root.rglob("*"), key=lambda item: item.as_posix().lower()):
        if filesystem_path.is_symlink():
            raise PackFormatError(f"symlinks are forbidden in source tree: {filesystem_path}")
        if filesystem_path.is_dir():
            continue
        if not filesystem_path.is_file():
            raise PackFormatError(f"non-regular source entry is forbidden: {filesystem_path}")
        internal = canonical_internal_path(filesystem_path.relative_to(root).as_posix())
        entries.append(PackEntry(internal, filesystem_path.read_bytes()))

    return _normalise_entries(entries)


def _is_within(path: Path, directory: Path) -> bool:
    try:
        path.relative_to(directory)
        return True
    except ValueError:
        return False


def pack_directory(
    root: os.PathLike[str] | str,
    destination: os.PathLike[str] | str,
) -> Path:
    """Collect a source tree and atomically write it as a deterministic pack."""

    root_path = Path(root).resolve()
    destination_path = Path(destination).resolve()
    if _is_within(destination_path, root_path):
        raise PackFormatError("destination must be outside the packed source tree")
    return write_pack_file(destination_path, collect_directory(root_path))


def _load_pack(path: str) -> bytes:
    return Path(path).read_bytes()


def _print_json(value: object) -> None:
    print(json.dumps(value, indent=2, sort_keys=True))


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    pack = subparsers.add_parser("pack", help="pack a directory as deterministic PFH4 Mod")
    pack.add_argument("source", help="source directory")
    pack.add_argument("destination", help="output .pack path (must be outside source)")

    verify = subparsers.add_parser("verify", help="strictly validate a generated pack")
    verify.add_argument("pack", help=".pack path")
    verify.add_argument("--json", action="store_true", help="emit the full JSON report")

    listing = subparsers.add_parser("list", help="list paths in a validated generated pack")
    listing.add_argument("pack", help=".pack path")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    arguments = parser.parse_args(argv)
    try:
        if arguments.command == "pack":
            output = pack_directory(arguments.source, arguments.destination)
            report = validate_pack(output.read_bytes())
            print(f"wrote {output} ({report['file_count']} files, {report['sha256']})")
            return 0
        if arguments.command == "verify":
            report = validate_pack(_load_pack(arguments.pack))
            if arguments.json:
                _print_json(report)
            else:
                print(
                    f"valid deterministic PFH4 Mod: {report['file_count']} files, "
                    f"sha256 {report['sha256']}"
                )
            return 0
        if arguments.command == "list":
            archive = read_pack(_load_pack(arguments.pack))
            for entry in archive.entries:
                print(f"{len(entry.data):10d}  {entry.path}")
            return 0
    except (OSError, PackFormatError, TypeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    parser.error("unknown command")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
