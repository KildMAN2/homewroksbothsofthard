import importlib.util
import sys
import time
import types
from pathlib import Path

# Stub pyperf so benchmark modules can be imported without pyperf installed.
if "pyperf" not in sys.modules:
    sys.modules["pyperf"] = types.SimpleNamespace(perf_counter=time.perf_counter, Runner=object)


ROOT = Path(__file__).resolve().parent
OPT_PATH = ROOT / "run_benchmark_optimized.py"


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


def compare_state(sys_a, sys_b):
    max_pos_diff = 0.0
    max_vel_diff = 0.0

    for (ra, va, _), (rb, vb, _) in zip(sys_a, sys_b):
        for a, b in zip(ra, rb):
            max_pos_diff = max(max_pos_diff, abs(a - b))
        for a, b in zip(va, vb):
            max_vel_diff = max(max_vel_diff, abs(a - b))

    return max_pos_diff, max_vel_diff


def fmt_vec(v):
    return f"[{v[0]:+.15e}, {v[1]:+.15e}, {v[2]:+.15e}]"


def main():
    opt = load_module("nbody_optimized", OPT_PATH)

    baseline_bodies = clone_bodies(opt.BODIES)
    opt_bodies = clone_bodies(opt.BODIES)

    baseline_system = list(baseline_bodies.values())
    opt_system = list(opt_bodies.values())

    baseline_pairs = combinations_ref(baseline_system)
    opt_pairs = opt.combinations(opt_system)

    # Complete correctness run uses the benchmark's default iteration count.
    dt = 0.01
    steps = opt.DEFAULT_ITERATIONS

    offset_momentum_original(baseline_bodies[opt.DEFAULT_REFERENCE], baseline_system)
    opt.offset_momentum(opt_bodies[opt.DEFAULT_REFERENCE], opt_system)

    advance_original(dt, steps, baseline_system, baseline_pairs)
    opt.advance(dt, steps, opt_system, opt_pairs)

    e_original = report_energy_original(baseline_system, baseline_pairs)
    e_opt = opt.report_energy(opt_system, opt_pairs)

    max_pos_diff, max_vel_diff = compare_state(baseline_system, opt_system)
    energy_diff = abs(e_original - e_opt)

    tol = 1e-12
    ok = max_pos_diff <= tol and max_vel_diff <= tol and energy_diff <= tol

    print(f"steps={steps}")
    print(f"energy_final_original={e_original:.15e}")
    print(f"energy_final_optimized={e_opt:.15e}")
    print(f"abs_energy_final_diff={energy_diff:.3e}")
    print(f"max_position_abs_diff={max_pos_diff:.3e}")
    print(f"max_velocity_abs_diff={max_vel_diff:.3e}")
    print(f"tolerance={tol:.1e}")

    names = list(opt.BODIES.keys())
    print("\nFINAL_POSITIONS_AND_VELOCITIES")
    for name, (orig, new) in zip(names, zip(baseline_system, opt_system)):
        (r0, v0, _) = orig
        (r1, v1, _) = new
        print(f"body={name}")
        print(f"  pos_original={fmt_vec(r0)}")
        print(f"  pos_optimized={fmt_vec(r1)}")
        print(f"  vel_original={fmt_vec(v0)}")
        print(f"  vel_optimized={fmt_vec(v1)}")

    if not ok:
        print("\nCORRECTNESS_CHECK=FAIL")
        raise SystemExit(1)

    print("\nCORRECTNESS_CHECK=PASS")


if __name__ == "__main__":
    main()
