"""Thin wrapper that runs the shared correctness check for final."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_attempt_correctness import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main([sys.argv[0], "final"]))
