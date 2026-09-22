"""
Windows-side wall-clock benchmark of the pyflate original + each optimized
attempt. This is a preliminary comparison — the OFFICIAL numbers are
collected on the course QEMU VM with `perf stat` + pyperformance. See
docs/06_final_software.md for the official pipeline.

Runs each of {original, attempt1, attempt2, attempt3, final} for N iterations
back-to-back, then reports mean/min/stddev of the timed loop, plus improvement
% vs the original.

Usage:
    python subPyflate/scripts/windows_bench.py [--loops N] [--repeats R]

Default: 3 loops per iteration, 5 iterations. That's 15 full decompressions
per attempt. Total wall-clock ~ 15 * (decompress time). Adjust with --loops
and --repeats if it's too slow.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import statistics
import sys
import time
from pathlib import Path


REFERENCE_MD5 = "afa004a630fe072901b1d9628b960974"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def find_workload(root: Path) -> Path:
    local = root / "original/bm_pyflate/data/interpreter.tar.bz2"
    if local.exists():
        return local
    import pyperformance
    packaged = (
        Path(pyperformance.__file__).parent
        / "data-files/benchmarks/bm_pyflate/data/interpreter.tar.bz2"
    )
    return packaged


def bench_one_call(module, workload: Path, loops: int) -> tuple[float, str]:
    """Time `loops` back-to-back decompressions through module.bzip2_main.

    Returns (elapsed_seconds, md5). Mirrors the timed region of
    bench_pyflake() in the pyflate benchmark itself.
    """
    fp = workload.open("rb")
    try:
        t0 = time.perf_counter()
        out = None
        for _ in range(loops):
            fp.seek(0)
            field = module.RBitfield(fp)
            magic = field.readbits(16)
            if magic == 0x1f8b:
                out = module.gzip_main(field)
            elif magic == 0x425a:
                out = module.bzip2_main(field)
            else:
                raise RuntimeError(f"unknown magic {magic:x}")
        dt = time.perf_counter() - t0
    finally:
        fp.close()
    return dt, hashlib.md5(out).hexdigest()


def summarize(times: list[float]) -> dict:
    return {
        "mean": statistics.mean(times),
        "min": min(times),
        "max": max(times),
        "stddev": statistics.stdev(times) if len(times) > 1 else 0.0,
        "n": len(times),
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--loops", type=int, default=3,
                        help="decompressions per timed iteration")
    parser.add_argument("--repeats", type=int, default=5,
                        help="timed iterations per attempt")
    args = parser.parse_args(argv[1:])

    root = Path(__file__).resolve().parents[1]
    workload = find_workload(root)
    print(f"Workload: {workload}  size={workload.stat().st_size} bytes")
    print(f"Loops per iteration: {args.loops}   Repeats: {args.repeats}")
    print(f"Python: {sys.version.split()[0]}")
    print("Note: Windows wall-clock; OFFICIAL numbers collected on the VM"
          " with perf stat + pyperformance.")
    print()

    variants = [
        ("original", root / "original/bm_pyflate/run_benchmark.py"),
        ("attempt1", root / "optimized/attempt1/run_benchmark.py"),
        ("attempt2", root / "optimized/attempt2/run_benchmark.py"),
        ("attempt3", root / "optimized/attempt3/run_benchmark.py"),
        ("final",    root / "optimized/final/run_benchmark.py"),
    ]

    results = {}
    for name, path in variants:
        module = load_module(f"pyflate_{name}", path)
        times: list[float] = []
        for i in range(args.repeats):
            dt, md5 = bench_one_call(module, workload, args.loops)
            times.append(dt)
            print(f"  [{name}] iter {i+1}/{args.repeats}: "
                  f"{dt:.4f} s  md5={md5}"
                  f"  {'OK' if md5 == REFERENCE_MD5 else 'MISMATCH'}")
        results[name] = summarize(times)
        print(f"  [{name}] mean={results[name]['mean']:.4f}s "
              f"min={results[name]['min']:.4f}s "
              f"stddev={results[name]['stddev']:.4f}s")
        print()

    baseline = results["original"]["mean"]

    print("=" * 74)
    print("Summary (Windows preliminary — NOT the official VM numbers)")
    print("=" * 74)
    header = f"{'Version':<12}{'mean (s)':>12}{'min (s)':>12}{'stddev':>12}{'improvement':>14}"
    print(header)
    print("-" * len(header))
    for name, _ in variants:
        r = results[name]
        if name == "original":
            improve = "—"
        else:
            improve = f"{(baseline - r['mean']) / baseline * 100:+.2f}%"
        print(f"{name:<12}{r['mean']:>12.4f}{r['min']:>12.4f}{r['stddev']:>12.4f}{improve:>14}")
    print()

    # Machine-readable dump for the docs.
    dump = root / "results/windows_preliminary.txt"
    with dump.open("w", encoding="utf-8") as fp:
        fp.write("Pyflate Windows preliminary results\n")
        fp.write(f"Python: {sys.version.split()[0]}\n")
        fp.write(f"Workload: {workload}\n")
        fp.write(f"Loops per iteration: {args.loops}\n")
        fp.write(f"Iterations per variant: {args.repeats}\n")
        fp.write("Timing method: time.perf_counter around "
                 "bzip2_main / gzip_main (mirrors bench_pyflake).\n")
        fp.write("These are WINDOWS PRELIMINARY numbers. Official VM numbers"
                 " are collected with perf stat + pyperformance.\n\n")
        fp.write(f"{'variant':<12}{'mean':>12}{'min':>12}{'stddev':>12}{'improvement':>14}\n")
        for name, _ in variants:
            r = results[name]
            if name == "original":
                improve = "0.00%"
            else:
                improve = f"{(baseline - r['mean']) / baseline * 100:+.2f}%"
            fp.write(f"{name:<12}{r['mean']:>12.4f}{r['min']:>12.4f}"
                     f"{r['stddev']:>12.4f}{improve:>14}\n")
    print(f"Written: {dump}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
