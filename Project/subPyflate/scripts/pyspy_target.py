"""Standalone target for py-spy: decompress the pyflate workload N times.

Usage: python pyspy_target.py {original|attempt1|attempt2|attempt3|final} [loops]

Runs the full bench_pyflake path (magic detection + bzip2_main) so py-spy
samples the same call tree the pyperformance benchmark measures.
"""
from __future__ import annotations

import importlib.util
import sys
import time
from pathlib import Path


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: pyspy_target.py {original|attempt1|attempt2|attempt3|final} [loops]",
              file=sys.stderr)
        return 2
    which = sys.argv[1]
    loops = int(sys.argv[2]) if len(sys.argv) > 2 else 20

    root = Path(__file__).resolve().parents[1]
    if which == "original":
        path = root / "original/bm_pyflate/run_benchmark.py"
    else:
        path = root / f"optimized/{which}/run_benchmark.py"
    workload = root / "original/bm_pyflate/data/interpreter.tar.bz2"

    module = load(f"pyflate_{which}", path)
    t0 = time.perf_counter()
    for _ in range(loops):
        with open(workload, "rb") as fp:
            field = module.RBitfield(fp)
            magic = field.readbits(16)
            if magic == 0x1f8b:
                module.gzip_main(field)
            elif magic == 0x425a:
                module.bzip2_main(field)
            else:
                raise RuntimeError(f"unknown magic {magic:x}")
    dt = time.perf_counter() - t0
    print(f"{which}: {loops} decompressions in {dt:.3f} s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
