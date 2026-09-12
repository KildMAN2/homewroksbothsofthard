"""
N-body benchmark from the Computer Language Benchmarks Game.

V4 loop-unrolled + sqrt + invariant precompute copy:
- Starts from V3 unrolled implementation.
- Keeps sqrt-based inverse-distance expression.
- Precomputes only invariant dt*mass constants per advance() call.
- Preserves original interaction order: 0-1, 0-2, 0-3, 0-4, 1-2, 1-3, 1-4, 2-3, 2-4, 3-4.
"""

import math
import pyperf

__contact__ = "collinwinter@google.com (Collin Winter)"
DEFAULT_ITERATIONS = 20000
DEFAULT_REFERENCE = 'sun'


def combinations(l):
    """Pure-Python implementation of itertools.combinations(l, 2)."""
    result = []
    for x in range(len(l) - 1):
        ls = l[x + 1:]
        for y in ls:
            result.append((l[x], y))
    return result


PI = 3.14159265358979323
SOLAR_MASS = 4 * PI * PI
DAYS_PER_YEAR = 365.24

BODIES = {
    'sun': ([0.0, 0.0, 0.0], [0.0, 0.0, 0.0], SOLAR_MASS),

    'jupiter': ([4.84143144246472090e+00,
                 -1.16032004402742839e+00,
                 -1.03622044471123109e-01],
                [1.66007664274403694e-03 * DAYS_PER_YEAR,
                 7.69901118419740425e-03 * DAYS_PER_YEAR,
                 -6.90460016972063023e-05 * DAYS_PER_YEAR],
                9.54791938424326609e-04 * SOLAR_MASS),

    'saturn': ([8.34336671824457987e+00,
                4.12479856412430479e+00,
                -4.03523417114321381e-01],
               [-2.76742510726862411e-03 * DAYS_PER_YEAR,
                4.99852801234917238e-03 * DAYS_PER_YEAR,
                2.30417297573763929e-05 * DAYS_PER_YEAR],
               2.85885980666130812e-04 * SOLAR_MASS),

    'uranus': ([1.28943695621391310e+01,
                -1.51111514016986312e+01,
                -2.23307578892655734e-01],
               [2.96460137564761618e-03 * DAYS_PER_YEAR,
                2.37847173959480950e-03 * DAYS_PER_YEAR,
                -2.96589568540237556e-05 * DAYS_PER_YEAR],
               4.36624404335156298e-05 * SOLAR_MASS),

    'neptune': ([1.53796971148509165e+01,
                 -2.59193146099879641e+01,
                 1.79258772950371181e-01],
                [2.68067772490389322e-03 * DAYS_PER_YEAR,
                 1.62824170038242295e-03 * DAYS_PER_YEAR,
                 -9.51592254519715870e-05 * DAYS_PER_YEAR],
                5.15138902046611451e-05 * SOLAR_MASS)}


SYSTEM = list(BODIES.values())
PAIRS = combinations(SYSTEM)


def advance(dt, n, bodies=SYSTEM, pairs=PAIRS):
    (r0, v0, m0) = bodies[0]
    (r1, v1, m1) = bodies[1]
    (r2, v2, m2) = bodies[2]
    (r3, v3, m3) = bodies[3]
    (r4, v4, m4) = bodies[4]

    # Invariant for the full advance() call: dt and masses are constant.
    dm0 = dt * m0
    dm1 = dt * m1
    dm2 = dt * m2
    dm3 = dt * m3
    dm4 = dt * m4

    for _ in range(n):
        # 0-1
        vx0, vy0, vz0 = v0
        vx1, vy1, vz1 = v1
        dx = r0[0] - r1[0]
        dy = r0[1] - r1[1]
        dz = r0[2] - r1[2]
        d2 = dx * dx + dy * dy + dz * dz
        inv_r3 = 1.0 / (d2 * math.sqrt(d2))
        b0m = dm0 * inv_r3
        b1m = dm1 * inv_r3
        vx0 -= dx * b1m
        vy0 -= dy * b1m
        vz0 -= dz * b1m
        vx1 += dx * b0m
        vy1 += dy * b0m
        vz1 += dz * b0m
        v0[0], v0[1], v0[2] = vx0, vy0, vz0
        v1[0], v1[1], v1[2] = vx1, vy1, vz1

        # 0-2
        vx0, vy0, vz0 = v0
        vx2, vy2, vz2 = v2
        dx = r0[0] - r2[0]
        dy = r0[1] - r2[1]
        dz = r0[2] - r2[2]
        d2 = dx * dx + dy * dy + dz * dz
        inv_r3 = 1.0 / (d2 * math.sqrt(d2))
        b0m = dm0 * inv_r3
        b2m = dm2 * inv_r3
        vx0 -= dx * b2m
        vy0 -= dy * b2m
        vz0 -= dz * b2m
        vx2 += dx * b0m
        vy2 += dy * b0m
        vz2 += dz * b0m
        v0[0], v0[1], v0[2] = vx0, vy0, vz0
        v2[0], v2[1], v2[2] = vx2, vy2, vz2

        # 0-3
        vx0, vy0, vz0 = v0
        vx3, vy3, vz3 = v3
        dx = r0[0] - r3[0]
        dy = r0[1] - r3[1]
        dz = r0[2] - r3[2]
        d2 = dx * dx + dy * dy + dz * dz
        inv_r3 = 1.0 / (d2 * math.sqrt(d2))
        b0m = dm0 * inv_r3
        b3m = dm3 * inv_r3
        vx0 -= dx * b3m
        vy0 -= dy * b3m
        vz0 -= dz * b3m
        vx3 += dx * b0m
        vy3 += dy * b0m
        vz3 += dz * b0m
        v0[0], v0[1], v0[2] = vx0, vy0, vz0
        v3[0], v3[1], v3[2] = vx3, vy3, vz3

        # 0-4
        vx0, vy0, vz0 = v0
        vx4, vy4, vz4 = v4
        dx = r0[0] - r4[0]
        dy = r0[1] - r4[1]
        dz = r0[2] - r4[2]
        d2 = dx * dx + dy * dy + dz * dz
        inv_r3 = 1.0 / (d2 * math.sqrt(d2))
        b0m = dm0 * inv_r3
        b4m = dm4 * inv_r3
        vx0 -= dx * b4m
        vy0 -= dy * b4m
        vz0 -= dz * b4m
        vx4 += dx * b0m
        vy4 += dy * b0m
        vz4 += dz * b0m
        v0[0], v0[1], v0[2] = vx0, vy0, vz0
        v4[0], v4[1], v4[2] = vx4, vy4, vz4

        # 1-2
        vx1, vy1, vz1 = v1
        vx2, vy2, vz2 = v2
        dx = r1[0] - r2[0]
        dy = r1[1] - r2[1]
        dz = r1[2] - r2[2]
        d2 = dx * dx + dy * dy + dz * dz
        inv_r3 = 1.0 / (d2 * math.sqrt(d2))
        b1m = dm1 * inv_r3
        b2m = dm2 * inv_r3
        vx1 -= dx * b2m
        vy1 -= dy * b2m
        vz1 -= dz * b2m
        vx2 += dx * b1m
        vy2 += dy * b1m
        vz2 += dz * b1m
        v1[0], v1[1], v1[2] = vx1, vy1, vz1
        v2[0], v2[1], v2[2] = vx2, vy2, vz2

        # 1-3
        vx1, vy1, vz1 = v1
        vx3, vy3, vz3 = v3
        dx = r1[0] - r3[0]
        dy = r1[1] - r3[1]
        dz = r1[2] - r3[2]
        d2 = dx * dx + dy * dy + dz * dz
        inv_r3 = 1.0 / (d2 * math.sqrt(d2))
        b1m = dm1 * inv_r3
        b3m = dm3 * inv_r3
        vx1 -= dx * b3m
        vy1 -= dy * b3m
        vz1 -= dz * b3m
        vx3 += dx * b1m
        vy3 += dy * b1m
        vz3 += dz * b1m
        v1[0], v1[1], v1[2] = vx1, vy1, vz1
        v3[0], v3[1], v3[2] = vx3, vy3, vz3

        # 1-4
        vx1, vy1, vz1 = v1
        vx4, vy4, vz4 = v4
        dx = r1[0] - r4[0]
        dy = r1[1] - r4[1]
        dz = r1[2] - r4[2]
        d2 = dx * dx + dy * dy + dz * dz
        inv_r3 = 1.0 / (d2 * math.sqrt(d2))
        b1m = dm1 * inv_r3
        b4m = dm4 * inv_r3
        vx1 -= dx * b4m
        vy1 -= dy * b4m
        vz1 -= dz * b4m
        vx4 += dx * b1m
        vy4 += dy * b1m
        vz4 += dz * b1m
        v1[0], v1[1], v1[2] = vx1, vy1, vz1
        v4[0], v4[1], v4[2] = vx4, vy4, vz4

        # 2-3
        vx2, vy2, vz2 = v2
        vx3, vy3, vz3 = v3
        dx = r2[0] - r3[0]
        dy = r2[1] - r3[1]
        dz = r2[2] - r3[2]
        d2 = dx * dx + dy * dy + dz * dz
        inv_r3 = 1.0 / (d2 * math.sqrt(d2))
        b2m = dm2 * inv_r3
        b3m = dm3 * inv_r3
        vx2 -= dx * b3m
        vy2 -= dy * b3m
        vz2 -= dz * b3m
        vx3 += dx * b2m
        vy3 += dy * b2m
        vz3 += dz * b2m
        v2[0], v2[1], v2[2] = vx2, vy2, vz2
        v3[0], v3[1], v3[2] = vx3, vy3, vz3

        # 2-4
        vx2, vy2, vz2 = v2
        vx4, vy4, vz4 = v4
        dx = r2[0] - r4[0]
        dy = r2[1] - r4[1]
        dz = r2[2] - r4[2]
        d2 = dx * dx + dy * dy + dz * dz
        inv_r3 = 1.0 / (d2 * math.sqrt(d2))
        b2m = dm2 * inv_r3
        b4m = dm4 * inv_r3
        vx2 -= dx * b4m
        vy2 -= dy * b4m
        vz2 -= dz * b4m
        vx4 += dx * b2m
        vy4 += dy * b2m
        vz4 += dz * b2m
        v2[0], v2[1], v2[2] = vx2, vy2, vz2
        v4[0], v4[1], v4[2] = vx4, vy4, vz4

        # 3-4
        vx3, vy3, vz3 = v3
        vx4, vy4, vz4 = v4
        dx = r3[0] - r4[0]
        dy = r3[1] - r4[1]
        dz = r3[2] - r4[2]
        d2 = dx * dx + dy * dy + dz * dz
        inv_r3 = 1.0 / (d2 * math.sqrt(d2))
        b3m = dm3 * inv_r3
        b4m = dm4 * inv_r3
        vx3 -= dx * b4m
        vy3 -= dy * b4m
        vz3 -= dz * b4m
        vx4 += dx * b3m
        vy4 += dy * b3m
        vz4 += dz * b3m
        v3[0], v3[1], v3[2] = vx3, vy3, vz3
        v4[0], v4[1], v4[2] = vx4, vy4, vz4

        for (r, v, _) in bodies:
            x, y, z = r
            vx, vy, vz = v
            x += dt * vx
            y += dt * vy
            z += dt * vz
            r[0], r[1], r[2] = x, y, z


def report_energy(bodies=SYSTEM, pairs=PAIRS, e=0.0):
    for (((x1, y1, z1), _, m1),
         ((x2, y2, z2), _, m2)) in pairs:
        dx = x1 - x2
        dy = y1 - y2
        dz = z1 - z2
        e -= (m1 * m2) / ((dx * dx + dy * dy + dz * dz) ** 0.5)
    for (_, [vx, vy, vz], m) in bodies:
        e += m * (vx * vx + vy * vy + vz * vz) / 2.0
    return e


def offset_momentum(ref, bodies=SYSTEM, px=0.0, py=0.0, pz=0.0):
    for (_, [vx, vy, vz], m) in bodies:
        px -= vx * m
        py -= vy * m
        pz -= vz * m
    (_, v, m) = ref
    v[0] = px / m
    v[1] = py / m
    v[2] = pz / m


def bench_nbody(loops, reference, iterations):
    offset_momentum(BODIES[reference])

    range_it = range(loops)
    t0 = pyperf.perf_counter()

    for _ in range_it:
        report_energy()
        advance(0.01, iterations)
        report_energy()

    return pyperf.perf_counter() - t0


def add_cmdline_args(cmd, args):
    cmd.extend(("--iterations", str(args.iterations)))


if __name__ == '__main__':
    runner = pyperf.Runner(add_cmdline_args=add_cmdline_args)
    runner.metadata['description'] = "n-body benchmark"
    runner.argparser.add_argument("--iterations",
                                  type=int, default=DEFAULT_ITERATIONS,
                                  help="Number of nbody advance() iterations "
                                       "(default: %s)" % DEFAULT_ITERATIONS)
    runner.argparser.add_argument("--reference",
                                  type=str, default=DEFAULT_REFERENCE,
                                  help="nbody reference (default: %s)"
                                       % DEFAULT_REFERENCE)

    args = runner.parse_args()
    runner.bench_time_func('nbody', bench_nbody,
                           args.reference, args.iterations)

