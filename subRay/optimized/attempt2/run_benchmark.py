"""
Optimization Attempt 2 for the raytrace benchmark.

This version preserves Attempt 1's scalar data path and applies one additional
optimization: hoisting frequently used global lookups and helper references into
local variables in the hottest loops.
"""

import array
import math

import pyperf


DEFAULT_WIDTH = 100
DEFAULT_HEIGHT = 100
EPSILON = 0.00001
SPECULAR_COEFFICIENT = 0.2
LAMBERT_COEFFICIENT = 0.6
AMBIENT_COEFFICIENT = 1.0 - SPECULAR_COEFFICIENT - LAMBERT_COEFFICIENT
PLANE_BASE_COLOUR = (1.0, 1.0, 1.0)
PLANE_OTHER_COLOUR = (0.0, 0.0, 0.0)


class Canvas(object):

    def __init__(self, width, height):
        self.bytes = array.array('B', [0] * (width * height * 3))
        for i in range(width * height):
            self.bytes[i * 3 + 2] = 255
        self.width = width
        self.height = height

    def plot(self, x, y, r, g, b):
        i = ((self.height - y - 1) * self.width + x) * 3
        self.bytes[i] = max(0, min(255, int(r * 255)))
        self.bytes[i + 1] = max(0, min(255, int(g * 255)))
        self.bytes[i + 2] = max(0, min(255, int(b * 255)))

    def write_ppm(self, filename):
        header = 'P6 %d %d 255\n' % (self.width, self.height)
        with open(filename, "wb") as fp:
            fp.write(header.encode('ascii'))
            fp.write(self.bytes.tobytes())


def normalize(x, y, z):
    inv = 1.0 / math.sqrt(x * x + y * y + z * z)
    return x * inv, y * inv, z * inv


def reflect(vx, vy, vz, nx, ny, nz):
    projection = 2.0 * (vx * nx + vy * ny + vz * nz)
    return vx - projection * nx, vy - projection * ny, vz - projection * nz


def sphere_intersection(px, py, pz, dx, dy, dz, cx, cy, cz, radius):
    cpx = cx - px
    cpy = cy - py
    cpz = cz - pz
    v = cpx * dx + cpy * dy + cpz * dz
    discriminant = (radius * radius) - ((cpx * cpx + cpy * cpy + cpz * cpz) - v * v)
    if discriminant < 0.0:
        return None
    return v - math.sqrt(discriminant)


def halfspace_intersection(dx, dy, dz, nx, ny, nz):
    projection = dx * nx + dy * ny + dz * nz
    if projection:
        return 1.0 / -projection
    return None


def checkerboard_base_colour(px, py, pz):
    # Preserve the original behavior exactly: checkSize scaling was computed but
    # not stored, so parity uses the unscaled coordinates.
    if ((int(abs(px) + 0.5)
         + int(abs(py) + 0.5)
         + int(abs(pz) + 0.5)) % 2):
        return PLANE_OTHER_COLOUR
    return PLANE_BASE_COLOUR


def visible_light(px, py, pz, ldx, ldy, ldz, spheres):
    for cx, cy, cz, radius, _, _, _ in spheres:
        t = sphere_intersection(px, py, pz, ldx, ldy, ldz, cx, cy, cz, radius)
        if t is not None and t > EPSILON:
            return False

    plane_t = halfspace_intersection(ldx, ldy, ldz, 0.0, 1.0, 0.0)
    if plane_t is not None and plane_t > EPSILON:
        return False
    return True


def ray_colour(px, py, pz, dx, dy, dz, depth, spheres, lights):
    normalize_fn = normalize
    reflect_fn = reflect
    sphere_intersection_fn = sphere_intersection
    visible_light_fn = visible_light
    eps = EPSILON
    spec_coeff = SPECULAR_COEFFICIENT
    lamb_coeff = LAMBERT_COEFFICIENT
    amb_coeff = AMBIENT_COEFFICIENT

    if depth > 3:
        return 0.0, 0.0, 0.0

    best_kind = None
    best_t = None
    best_sphere = None

    for sphere in spheres:
        cx, cy, cz, radius, _, _, _ = sphere
        t = sphere_intersection_fn(px, py, pz, dx, dy, dz, cx, cy, cz, radius)
        if t is not None and t > -eps:
            if best_t is None or t < best_t:
                best_t = t
                best_kind = "sphere"
                best_sphere = sphere

    plane_t = halfspace_intersection(dx, dy, dz, 0.0, 1.0, 0.0)
    if plane_t is not None and plane_t > -eps:
        if best_t is None or plane_t < best_t:
            best_t = plane_t
            best_kind = "halfspace"

    if best_kind is None:
        return 0.0, 0.0, 0.0

    hit_x = px + dx * best_t
    hit_y = py + dy * best_t
    hit_z = pz + dz * best_t

    if best_kind == "sphere":
        cx, cy, cz, _, base_r, base_g, base_b = best_sphere
        normal_x, normal_y, normal_z = normalize_fn(hit_x - cx, hit_y - cy, hit_z - cz)
        base_r, base_g, base_b = base_r, base_g, base_b
    else:
        normal_x, normal_y, normal_z = 0.0, 1.0, 0.0
        base_r, base_g, base_b = checkerboard_base_colour(hit_x, hit_y, hit_z)

    colour_r = 0.0
    colour_g = 0.0
    colour_b = 0.0

    if spec_coeff > 0.0:
        reflected_x, reflected_y, reflected_z = reflect_fn(dx, dy, dz, normal_x, normal_y, normal_z)
        reflected_x, reflected_y, reflected_z = normalize_fn(reflected_x, reflected_y, reflected_z)
        reflected_r, reflected_g, reflected_b = ray_colour(
            hit_x, hit_y, hit_z,
            reflected_x, reflected_y, reflected_z,
            depth + 1,
            spheres,
            lights,
        )
        colour_r += spec_coeff * reflected_r
        colour_g += spec_coeff * reflected_g
        colour_b += spec_coeff * reflected_b

    if lamb_coeff > 0.0:
        lambert_amount = 0.0
        for light_x, light_y, light_z in lights:
            light_dx, light_dy, light_dz = normalize_fn(light_x - hit_x, light_y - hit_y, light_z - hit_z)
            if visible_light_fn(hit_x, hit_y, hit_z, light_dx, light_dy, light_dz, spheres):
                contribution = light_dx * normal_x + light_dy * normal_y + light_dz * normal_z
                if contribution > 0.0:
                    lambert_amount += contribution
        if lambert_amount > 1.0:
            lambert_amount = 1.0
        scale = lamb_coeff * lambert_amount
        colour_r += scale * base_r
        colour_g += scale * base_g
        colour_b += scale * base_b

    if amb_coeff > 0.0:
        colour_r += amb_coeff * base_r
        colour_g += amb_coeff * base_g
        colour_b += amb_coeff * base_b

    return colour_r, colour_g, colour_b


def bench_raytrace(loops, width, height, filename):
    range_it = range(loops)
    t0 = pyperf.perf_counter()
    normalize_fn = normalize
    ray_colour_fn = ray_colour

    for _ in range_it:
        canvas = Canvas(width, height)
        lights = (
            (30.0, 30.0, 10.0),
            (-10.0, 100.0, 30.0),
        )
        spheres = [
            (1.0, 3.0, -10.0, 2.0, 1.0, 1.0, 0.0),
        ]
        for y in range(6):
            fraction = y / 6.0
            spheres.append((-3.0 - y * 0.4, 2.3, -5.0, 0.4, fraction, 1.0 - fraction, 0.5))

        position_x = 0.0
        position_y = 1.8
        position_z = 10.0
        look_x = 0.0
        look_y = 3.0
        look_z = 0.0

        fov_radians = math.pi * (45.0 / 2.0) / 180.0
        half_width = math.tan(fov_radians)
        half_height = 0.75 * half_width
        full_width = half_width * 2.0
        full_height = half_height * 2.0
        pixel_width = full_width / (canvas.width - 1)
        pixel_height = full_height / (canvas.height - 1)

        eye_dx, eye_dy, eye_dz = normalize_fn(look_x - position_x, look_y - position_y, look_z - position_z)
        right_x, right_y, right_z = normalize_fn(-eye_dz, 0.0, eye_dx)
        up_x, up_y, up_z = normalize_fn(
            right_y * eye_dz - right_z * eye_dy,
            right_z * eye_dx - right_x * eye_dz,
            right_x * eye_dy - right_y * eye_dx,
        )

        for y in range(canvas.height):
            y_offset = y * pixel_height - half_height
            for x in range(canvas.width):
                x_offset = x * pixel_width - half_width
                ray_dx = eye_dx + right_x * x_offset + up_x * y_offset
                ray_dy = eye_dy + right_y * x_offset + up_y * y_offset
                ray_dz = eye_dz + right_z * x_offset + up_z * y_offset
                ray_dx, ray_dy, ray_dz = normalize_fn(ray_dx, ray_dy, ray_dz)
                colour_r, colour_g, colour_b = ray_colour_fn(
                    position_x, position_y, position_z,
                    ray_dx, ray_dy, ray_dz,
                    0,
                    spheres,
                    lights,
                )
                canvas.plot(x, y, colour_r, colour_g, colour_b)

    dt = pyperf.perf_counter() - t0

    if filename:
        canvas.write_ppm(filename)
    return dt


def add_cmdline_args(cmd, args):
    cmd.append("--width=%s" % args.width)
    cmd.append("--height=%s" % args.height)
    if args.filename:
        cmd.extend(("--filename", args.filename))


if __name__ == "__main__":
    runner = pyperf.Runner(add_cmdline_args=add_cmdline_args)
    cmd = runner.argparser
    cmd.add_argument("--width",
                     type=int, default=DEFAULT_WIDTH,
                     help="Image width (default: %s)" % DEFAULT_WIDTH)
    cmd.add_argument("--height",
                     type=int, default=DEFAULT_HEIGHT,
                     help="Image height (default: %s)" % DEFAULT_HEIGHT)
    cmd.add_argument("--filename", metavar="FILENAME.PPM",
                     help="Output filename of the PPM picture")

    args = runner.parse_args()
    runner.metadata['description'] = "Simple raytracer attempt2"
    runner.metadata['raytrace_width'] = args.width
    runner.metadata['raytrace_height'] = args.height

    runner.bench_time_func('raytrace_attempt2', bench_raytrace,
                           args.width, args.height,
                           args.filename)
