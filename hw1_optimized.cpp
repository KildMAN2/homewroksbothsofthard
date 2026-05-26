#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

uint32_t xorshift32(uint32_t &state) {
    uint32_t x = state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    state = x;
    return x;
}

void fill_image(std::vector<uint8_t> &img, uint32_t seed) {
    uint32_t state = seed;
    for (size_t i = 0; i < img.size(); ++i) {
        img[i] = static_cast<uint8_t>(xorshift32(state) & 0xFFu);
    }
}

uint64_t checksum(const std::vector<uint8_t> &img) {
    uint64_t acc = 1469598103934665603ull;
    for (size_t i = 0; i < img.size(); ++i) {
        acc ^= static_cast<uint64_t>(img[i]) + (i & 0xFFu);
        acc *= 1099511628211ull;
    }
    return acc;
}

void blur_step_optimized(const std::vector<uint8_t> &in,
                        std::vector<uint8_t> &out,
                        std::vector<uint16_t> &horiz,
                        int width,
                        int height) {
    out = in;

    for (int y = 0; y < height; ++y) {
        const int row = y * width;
        for (int x = 1; x < width - 1; ++x) {
            const int idx = row + x;
            horiz[idx] = static_cast<uint16_t>(in[idx - 1] + in[idx] + in[idx + 1]);
        }
    }

    for (int y = 1; y < height - 1; ++y) {
        const int row = y * width;
        const int row_up = row - width;
        const int row_dn = row + width;
        for (int x = 1; x < width - 1; ++x) {
            const int idx = row + x;
            const int sum = horiz[row_up + x] + horiz[idx] + horiz[row_dn + x];
            out[idx] = static_cast<uint8_t>(sum / 9);
        }
    }
}

}  // namespace

int main(int argc, char **argv) {
    if (argc != 5) {
        std::cerr << "Usage: " << argv[0] << " <width> <height> <iterations> <seed>\n";
        return 1;
    }

    const int width = std::stoi(argv[1]);
    const int height = std::stoi(argv[2]);
    const int iterations = std::stoi(argv[3]);
    const uint32_t seed = static_cast<uint32_t>(std::stoul(argv[4]));

    if (width < 3 || height < 3 || iterations < 1) {
        std::cerr << "width and height must be >= 3, iterations must be >= 1\n";
        return 1;
    }

    std::vector<uint8_t> a(static_cast<size_t>(width) * static_cast<size_t>(height));
    std::vector<uint8_t> b(a.size());
    std::vector<uint16_t> horiz(a.size());

    fill_image(a, seed);

    const auto start = std::chrono::high_resolution_clock::now();
    for (int i = 0; i < iterations; ++i) {
        blur_step_optimized(a, b, horiz, width, height);
        a.swap(b);
    }
    const auto end = std::chrono::high_resolution_clock::now();

    const auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

    std::cout << "RESULT checksum=" << checksum(a)
              << " width=" << width
              << " height=" << height
              << " iterations=" << iterations
              << "\n";
    std::cout << "TIME_MS " << elapsed_ms << "\n";
    return 0;
}
