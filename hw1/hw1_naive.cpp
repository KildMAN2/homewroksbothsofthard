#include <chrono>
#include <cstdint>
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

void fill_sequence(std::vector<uint8_t> &seq, uint32_t seed) {
    uint32_t s = seed;
    for (size_t i = 0; i < seq.size(); ++i) {
        seq[i] = static_cast<uint8_t>(xorshift32(s) & 0x3u);
    }
}

int motif_score_naive(uint16_t code) {
    const uint8_t a = static_cast<uint8_t>(code & 0x3u);
    const uint8_t b = static_cast<uint8_t>((code >> 2) & 0x3u);
    const uint8_t c = static_cast<uint8_t>((code >> 4) & 0x3u);
    const uint8_t d = static_cast<uint8_t>((code >> 6) & 0x3u);
    const uint8_t e = static_cast<uint8_t>((code >> 8) & 0x3u);

    int score = 0;

    if (a == c && c == e) {
        score += 5;
    }
    if (b == d) {
        score += 3;
    }
    if ((a + b + c + d + e) >= 8) {
        score += 2;
    }
    if (a == 0 && b == 1 && c == 2 && d == 3) {
        score += 7;
    }
    if (a == 3 && b == 2 && c == 1 && d == 0) {
        score += 7;
    }
    if ((a == 0 && e == 3) || (a == 3 && e == 0)) {
        score -= 2;
    }
    if ((b == 0 && d == 0) || (b == 3 && d == 3)) {
        score -= 1;
    }

    return score;
}

uint64_t checksum(const std::vector<uint8_t> &seq) {
    uint64_t acc = 1469598103934665603ull;
    for (size_t i = 0; i < seq.size(); ++i) {
        acc ^= (static_cast<uint64_t>(seq[i]) + (i & 0xFFu));
        acc *= 1099511628211ull;
    }
    return acc;
}

void evolve_step_naive(const std::vector<uint8_t> &in,
                      std::vector<uint8_t> &out,
                      int iteration) {
    const int n = static_cast<int>(in.size());

    for (int i = 0; i < n; ++i) {
        const int im2 = (i + n - 2) % n;
        const int im1 = (i + n - 1) % n;
        const int ip1 = (i + 1) % n;
        const int ip2 = (i + 2) % n;

        const uint16_t code = static_cast<uint16_t>(
            in[im2] |
            (in[im1] << 2) |
            (in[i] << 4) |
            (in[ip1] << 6) |
            (in[ip2] << 8));

        const int score = motif_score_naive(code);
        const uint8_t center = in[i];
        uint8_t next = static_cast<uint8_t>((center + (score & 0x3)) & 0x3);

        if (((score ^ iteration ^ i) & 1) != 0) {
            next ^= 0x1u;
        }

        out[i] = next;
    }
}

}  // namespace

int main(int argc, char **argv) {
    if (argc != 4) {
        std::cerr << "Usage: " << argv[0] << " <length> <iterations> <seed>\n";
        return 1;
    }

    const int length = std::stoi(argv[1]);
    const int iterations = std::stoi(argv[2]);
    const uint32_t seed = static_cast<uint32_t>(std::stoul(argv[3]));

    if (length < 8 || iterations < 1) {
        std::cerr << "length must be >= 8 and iterations must be >= 1\n";
        return 1;
    }

    std::vector<uint8_t> a(static_cast<size_t>(length));
    std::vector<uint8_t> b(static_cast<size_t>(length));

    fill_sequence(a, seed);

    const auto start = std::chrono::high_resolution_clock::now();
    for (int it = 0; it < iterations; ++it) {
        evolve_step_naive(a, b, it);
        a.swap(b);
    }
    const auto end = std::chrono::high_resolution_clock::now();

    size_t count_a = 0;
    size_t count_c = 0;
    size_t count_g = 0;
    size_t count_t = 0;
    for (uint8_t v : a) {
        if (v == 0) {
            ++count_a;
        } else if (v == 1) {
            ++count_c;
        } else if (v == 2) {
            ++count_g;
        } else {
            ++count_t;
        }
    }

    const auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
    std::cout << "RESULT checksum=" << checksum(a)
              << " len=" << length
              << " iterations=" << iterations
              << " A=" << count_a
              << " C=" << count_c
              << " G=" << count_g
              << " T=" << count_t
              << "\n";
    std::cout << "TIME_MS " << elapsed_ms << "\n";

    return 0;
}
