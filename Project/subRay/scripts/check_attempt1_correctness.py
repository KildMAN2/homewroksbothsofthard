from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path


def load_module(module_name: str, file_path: Path):
    spec = importlib.util.spec_from_file_location(module_name, file_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    root_dir = Path(__file__).resolve().parents[1]
    result_dir = root_dir / "results" / "attempt1"
    result_dir.mkdir(parents=True, exist_ok=True)

    original_path = root_dir / "original" / "bm_raytrace" / "run_benchmark.py"
    optimized_path = root_dir / "optimized" / "attempt1" / "run_benchmark.py"

    original = load_module("raytrace_original", original_path)
    optimized = load_module("raytrace_attempt1", optimized_path)

    original_ppm = result_dir / "correctness_original.ppm"
    optimized_ppm = result_dir / "correctness_attempt1.ppm"

    original_time = original.bench_raytrace(1, 32, 32, str(original_ppm))
    optimized_time = optimized.bench_raytrace(1, 32, 32, str(optimized_ppm))

    original_hash = sha256_file(original_ppm)
    optimized_hash = sha256_file(optimized_ppm)
    identical = original_ppm.read_bytes() == optimized_ppm.read_bytes()

    report = result_dir / "correctness_report.txt"
    report.write_text(
        "ATTEMPT=1\n"
        f"WIDTH=32\nHEIGHT=32\n"
        f"ORIGINAL_TIME={original_time:.12f}\n"
        f"OPTIMIZED_TIME={optimized_time:.12f}\n"
        f"ORIGINAL_SHA256={original_hash}\n"
        f"OPTIMIZED_SHA256={optimized_hash}\n"
        f"IDENTICAL={'YES' if identical else 'NO'}\n",
        encoding="utf-8",
    )

    print(report.read_text(encoding="utf-8"), end="")
    return 0 if identical else 1


if __name__ == "__main__":
    raise SystemExit(main())
