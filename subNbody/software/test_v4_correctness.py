import importlib.util
import sys
import time
import types
from pathlib import Path

# Stub pyperf so benchmark modules can be imported without pyperf installed.
if "pyperf" not in sys.modules:
    sys.modules["pyperf"] = types.SimpleNamespace(perf_counter=time.perf_counter, Runner=object)


ROOT = Path(__file__).resolve().parent
V4_PATH = ROOT / "run_benchmark_v4_precompute.py"


def load_module(module_name: str, file_path: Path):
    spec = importlib.util.spec_from_file_location(module_name, str(file_path))
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def combinations_ref(l):
    result = []
    for x in range(len(l) - 1):
        ls = l[x + 1:]
        for y in ls:
            result.append((l[x], y))
    return result


def advance_original(dt, n, bodies, pairs):
    for _ in range(n):
        for (([x1, y1, z1], v1, m1),
             ([x2, y2, z2], v2, m2)) in pairs:
            dx = x1 - x2
            dy = y1 - y2
            dz = z1 - z2
            mag = dt * ((dx * dx + dy * dy + dz * dz) ** (-1.5))
            b1m = m1 * mag
            b2m = m2 * mag
            v1[0] -= dx * b2m
            v1[1] -= dy * b2m
            v1[2] -= dz * b2m
            v2[0] += dx * b1m
            v2[1] += dy * b1m
            v2[2] += dz * b1m
        for (r, [vx, vy, vz], _) in bodies:
            r[0] += dt * vx
            r[1] += dt * vy
            r[2] += dt * vz


def report_energy_original(bodies, pairs, e=0.0):
    for (((x1, y1, z1), _, m1),
         ((x2, y2, z2), _, m2)) in pairs:
        dx = x1 - x2
        dy = y1 - y2
        dz = z1 - z2
        e -= (m1 * m2) / ((dx * dx + dy * dy + dz * dz) ** 0.5)
    for (_, [vx, vy, vz], m) in bodies:
        e += m * (vx * vx + vy * vy + vz * vz) / 2.0
    return e


def offset_momentum_original(ref, bodies, px=0.0, py=0.0, pz=0.0):
    for (_, [vx, vy, vz], m) in bodies:
        px -= vx * m
        py -= vy * m
        pz -= vz * m
    (_, v, m) = ref
    v[0] = px / m
    v[1] = py / m
    v[2] = pz / m


def clone_bodies(bodies_dict):
    return {
        name: ([r[0], r[1], r[2]], [v[0], v[1], v[2]], m)
        for name, (r, v, m) in bodies_dict.items()
    }


def max_state_diff(sys_a, sys_b):
    max_diff = 0.0
    for (ra, va, _), (rb, vb, _) in zip(sys_a, sys_b):
        for a, b in zip(ra, rb):
            max_diff = max(max_diff, abs(a - b))
        for a, b in zip(va, vb):
            max_diff = max(max_diff, abs(a - b))
    return max_diff


def main():
    v4 = load_module("nbody_v4", V4_PATH)

    baseline_bodies = clone_bodies(v4.BODIES)
    v4_bodies = clone_bodies(v4.BODIES)

    baseline_system = list(baseline_bodies.values())
    v4_system = list(v4_bodies.values())

    baseline_pairs = combinations_ref(baseline_system)
    v4_pairs = v4.combinations(v4_system)

    # Short correctness run, intentionally not a full benchmark.
    dt = 0.01
    steps = 100

    offset_momentum_original(baseline_bodies[v4.DEFAULT_REFERENCE], baseline_system)
    v4.offset_momentum(v4_bodies[v4.DEFAULT_REFERENCE], v4_system)

    e0_before = report_energy_original(baseline_system, baseline_pairs)
    e4_before = v4.report_energy(v4_system, v4_pairs)

    advance_original(dt, steps, baseline_system, baseline_pairs)
    v4.advance(dt, steps, v4_system, v4_pairs)

    e0_after = report_energy_original(baseline_system, baseline_pairs)
    e4_after = v4.report_energy(v4_system, v4_pairs)

    max_diff = max_state_diff(baseline_system, v4_system)
    e_before_diff = abs(e0_before - e4_before)
    e_after_diff = abs(e0_after - e4_after)

    tol = 1e-12
    ok = max_diff <= tol and e_before_diff <= tol and e_after_diff <= tol

    print(f"steps={steps}")
    print(f"energy_before_original={e0_before:.15e}")
    print(f"energy_before_v4={e4_before:.15e}")
    print(f"energy_after_original={e0_after:.15e}")
    print(f"energy_after_v4={e4_after:.15e}")
    print(f"abs_energy_before_diff={e_before_diff:.3e}")
    print(f"abs_energy_after_diff={e_after_diff:.3e}")
    print(f"max_state_abs_diff={max_diff:.3e}")
    print(f"tolerance={tol:.1e}")

    if not ok:
        print("CORRECTNESS_CHECK=FAIL")
        raise SystemExit(1)

    print("CORRECTNESS_CHECK=PASS")


if __name__ == "__main__":
    main()

