"""
Correctness check shared by every pyflate attempt.

Usage:
    python3 subPyflate/scripts/check_attempt_correctness.py <attemptN>

where <attemptN> is one of: attempt1, attempt2, attempt3, final.

The script:
  1. Loads the preserved original run_benchmark.py as a module.
  2. Loads the optimized attempt's run_benchmark.py as a module.
  3. Runs both through their own decompression path on the pyflate workload
     shipped with pyperformance (falls back to the local repo copy if that is
     ever added).
  4. Compares the produced bytes and MD5s them against the pyflate reference
     ("afa004a630fe072901b1d9628b960974").
  5. Writes results/<attempt>/correctness_report.txt (or, for the top-level
     mirror, results/<attempt>_correctness_report.txt).

`from __future__ import annotations` keeps this file compatible with the
Python 3.8+ requirement of the pyperformance benchmark packaging.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
import sys
from pathlib import Path


REFERENCE_MD5 = "afa004a630fe072901b1d9628b960974"


def load_module(module_name: str, file_path: Path):
    spec = importlib.util.spec_from_file_location(module_name, file_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {file_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def find_workload(root_dir: Path) -> Path:
    """Return the interpreter.tar.bz2 file used by the pyflate benchmark.

    Tries the local repository copy first (empty by default; used only if the
    user manually places the file there); falls back to the installed
    pyperformance package copy.
    """
    local = root_dir / "original" / "bm_pyflate" / "data" / "interpreter.tar.bz2"
    if local.exists():
        return local
    try:
        import pyperformance  # noqa: WPS433
    except ImportError as exc:
        raise SystemExit(
            "Cannot locate interpreter.tar.bz2: pyperformance is not "
            "installed and the local data copy is absent. Install "
            "pyperformance in this Python environment or copy the file "
            f"to {local}.") from exc
    packaged = (
        Path(pyperformance.__file__).parent
        / "data-files"
        / "benchmarks"
        / "bm_pyflate"
        / "data"
        / "interpreter.tar.bz2"
    )
    if not packaged.exists():
        raise SystemExit(
            f"pyperformance is installed but does not ship the pyflate data "
            f"file at {packaged}.")
    return packaged


def decompress_with_module(module, workload: Path) -> bytes:
    """Call `module.bzip2_main` / `module.gzip_main` directly on the workload.

    This bypasses pyperf timing so the check works even in environments
    without a functional pyperf.Runner.
    """
    with open(workload, "rb") as fp:
        field = module.RBitfield(fp)
        magic = field.readbits(16)
        if magic == 0x1f8b:
            return module.gzip_main(field)
        if magic == 0x425a:
            return module.bzip2_main(field)
    raise RuntimeError(f"unknown magic in {workload}")


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in {"attempt1", "attempt2", "attempt3", "final"}:
        print("Usage: check_attempt_correctness.py {attempt1|attempt2|attempt3|final}",
              file=sys.stderr)
        return 2

    which = argv[1]
    root_dir = Path(__file__).resolve().parents[1]
    workload = find_workload(root_dir)

    original_path = root_dir / "original" / "bm_pyflate" / "run_benchmark.py"
    optimized_path = root_dir / "optimized" / which / "run_benchmark.py"

    original = load_module("pyflate_original", original_path)
    optimized = load_module(f"pyflate_{which}", optimized_path)

    orig_bytes = decompress_with_module(original, workload)
    opt_bytes = decompress_with_module(optimized, workload)

    orig_md5 = hashlib.md5(orig_bytes).hexdigest()
    opt_md5 = hashlib.md5(opt_bytes).hexdigest()
    identical = orig_bytes == opt_bytes
    ref_ok = opt_md5 == REFERENCE_MD5

    result_dir = root_dir / "results" / which
    result_dir.mkdir(parents=True, exist_ok=True)
    report_lines = [
        f"ATTEMPT={which}",
        f"WORKLOAD={workload}",
        f"ORIGINAL_LEN={len(orig_bytes)}",
        f"OPTIMIZED_LEN={len(opt_bytes)}",
        f"ORIGINAL_MD5={orig_md5}",
        f"OPTIMIZED_MD5={opt_md5}",
        f"REFERENCE_MD5={REFERENCE_MD5}",
        f"MATCHES_REFERENCE={'YES' if ref_ok else 'NO'}",
        f"IDENTICAL={'YES' if identical else 'NO'}",
        "",
    ]
    body = "\n".join(report_lines)
    (result_dir / "correctness_report.txt").write_text(body, encoding="utf-8")
    # Mirror the shorter top-level filename used in subRay/results/.
    (root_dir / "results" / f"{which}_correctness_report.txt").write_text(
        body, encoding="utf-8")
    print(body, end="")
    return 0 if identical and ref_ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
