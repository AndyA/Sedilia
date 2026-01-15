#!/usr/bin/env python3

import argparse
import struct
from pathlib import Path
from typing import Iterable


def txt_to_zig(type: str) -> tuple[type, str]:
    zig_to_struct = {
        "i32": (int, ">i"),
        "i64": (int, ">q"),
        "f32": (float, ">f"),
        "f64": (float, ">d"),
    }
    if type not in zig_to_struct:
        raise ValueError(f"Unsupported type: {type}")
    return zig_to_struct[type]


def txt_to_bin(type: str, in_file: Path, out_file: Path) -> None:
    py_type, pack = txt_to_zig(type)
    with in_file.open("r", encoding="utf-8") as fin, out_file.open("wb") as fout:
        for lineno, raw in enumerate(fin, start=1):
            line = raw.strip()
            if not line:
                continue
            try:
                value = py_type(line)
            except ValueError as exc:
                raise ValueError(
                    f"Invalid {py_type.__name__} on line {lineno}: {line!r}"
                ) from exc
            fout.write(struct.pack(pack, value))


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=(
            "Convert a text file of numbers (one per line) to big-endian binary file."
        )
    )
    p.add_argument("type", help="Zig type")
    p.add_argument("input", type=Path, help="Input text file (one number per line)")
    p.add_argument("output", type=Path, help="Output binary file")
    return p.parse_args(argv)


def main() -> None:
    args = parse_args()
    if not args.input.exists():
        raise SystemExit(f"Input file does not exist: {args.input}")
    txt_to_bin(type=args.type, in_file=args.input, out_file=args.output)
    print(f"Wrote binary data to {args.output}")


if __name__ == "__main__":
    main()
