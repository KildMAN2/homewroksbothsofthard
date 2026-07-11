# Code Explanation: hw1_naive.cpp and hw1_optimized.cpp

---

## Purpose of the Code

These two programs are a **performance profiling experiment**. The goal is to implement the same computation twice — once in the most straightforward way (naive), and once with hardware-aware optimizations — then measure and explain the speedup.

The experiment demonstrates two classic CPU-level optimization techniques:

| Technique | Problem it solves |
|---|---|
| **Lookup table (LUT)** | Eliminates unpredictable branches in a scoring function |
| **Rolling window encoding** | Eliminates redundant memory loads in a sliding-window loop |

### Concrete Example: What "Same Computation, Faster" Means

Suppose `length=8`, `iterations=1`, `seed=42`. Both programs will:

1. Generate the **same** 8-base sequence from seed 42, e.g.: `[2, 0, 1, 3, 0, 2, 1, 0]`
2. For each position, read the 5-base window centered on it (wrapping around the ends)
3. Score the window and compute a new base
4. Produce the **same** output sequence and checksum

For position `i=2` (center base = `1`), the window is `[2, 0, 1, 3, 0]`:
- Pack into 10-bit code: `2 | (0<<2) | (1<<4) | (3<<6) | (0<<8)` = `0b0011010010` = `210`
- **Naive:** evaluate 7 `if` statements on the unpacked bases → score = +3 (rule 2: b==d, both 0)
- **Optimized:** look up `score_lut[210]` → same answer, zero branches

The final printed result — checksum, base counts, and structure — is **bit-for-bit identical** between both versions. Only the time differs.

### How to Run

```bash
# Build
g++ -O2 -o hw1_naive    hw1_naive.cpp
g++ -O2 -o hw1_optimized hw1_optimized.cpp

# Run  (length=4000000, iterations=50, seed=123456789)
./hw1_naive     4000000 50 123456789
./hw1_optimized 4000000 50 123456789
```

Both print the same `RESULT` line, e.g.:
```
RESULT checksum=11858510826495703989 A=999842 C=999645 G=1000406 T=1000107
TIME_MS 8684       ← naive
TIME_MS 553        ← optimized  (≈15.7× faster)
```

---

## The Problem: DNA Motif Cellular Automaton

Both programs simulate a **circular sequence** of 4 million bases (A, C, G, T — encoded as 0, 1, 2, 3 in 2 bits each). At every iteration, each position in the sequence is updated by looking at its two left and two right neighbors (a 5-base window), scoring the pattern according to biological-style rules, and computing a new base value. This repeats for 50 iterations.

Both programs take three arguments: `length iterations seed` and always produce the **exact same output** for the same input.

---

## What the Code Actually Does — Step-by-Step Example

Let's trace through a tiny sequence of **6 bases** for **1 iteration** to see exactly what happens.

### Step 1 — Initialize the sequence from a seed

The seed deterministically generates bases in `{0,1,2,3}` → `{A,C,G,T}`:

```
Index:    0    1    2    3    4    5
Base:     2    0    3    1    2    0      (G A T C G A)
```

The sequence is **circular** — index -1 wraps to index 5, index 6 wraps to index 0.

---

### Step 2 — For each position, read its 5-base window

Each position `i` looks at `[i-2, i-1, i, i+1, i+2]` (wrapping at ends):

| Position i | Window indices | Window values | Packed code (binary) |
|---|---|---|---|
| 0 | [4, 5, 0, 1, 2] | [2, 0, 2, 0, 3] | `11 00 10 00 10` = 562 |
| 1 | [5, 0, 1, 2, 3] | [0, 2, 0, 3, 1] | `01 11 00 10 00` = 456 |
| 2 | [0, 1, 2, 3, 4] | [2, 0, 3, 1, 2] | `10 01 11 00 10` = 626 |
| 3 | [1, 2, 3, 4, 5] | [0, 3, 1, 2, 0] | `00 10 01 11 00` = 156 |
| 4 | [2, 3, 4, 5, 0] | [3, 1, 2, 0, 2] | `10 00 10 01 11` = 551 |
| 5 | [3, 4, 5, 0, 1] | [1, 2, 0, 2, 0] | `00 10 00 10 01` = 137 |

---

### Step 3 — Score each window using the 7 rules

Take position `i=2`, window = `[2, 0, 3, 1, 2]` → a=2, b=0, c=3, d=1, e=2:

| Rule | Check | Result | Score |
|---|---|---|---|
| 1 | a==c && c==e → 2==3? | ✗ | +0 |
| 2 | b==d → 0==1? | ✗ | +0 |
| 3 | a+b+c+d+e = 8 >= 8? | ✓ | +2 |
| 4 | a==0,b==1,c==2,d==3? | ✗ | +0 |
| 5 | a==3,b==2,c==1,d==0? | ✗ | +0 |
| 6 | (a==0&&e==3)\|\|(a==3&&e==0)? | ✗ | +0 |
| 7 | (b==0&&d==0)\|\|(b==3&&d==3)? | ✗ | +0 |

**Total score = +2**

---

### Step 4 — Compute the new base

```cpp
uint8_t next = (in[i] + (score & 0x3)) & 0x3;
if (((score ^ iteration ^ i) & 1) != 0)
    next ^= 0x1;
```

For i=2, iteration=0, score=2:
- `next = (3 + (2 & 3)) & 3 = (3 + 2) & 3 = 5 & 3 = 1`
- `(2 ^ 0 ^ 2) & 1 = 0` → no flip
- **New base at position 2 = 1 (C)**  ← was 3 (T)

---

### Step 5 — After the full iteration

All 6 positions are updated simultaneously (reads from old buffer, writes to new buffer):

```
Before:  G  A  T  C  G  A   (2 0 3 1 2 0)
After:   ?  ?  C  ?  ?  ?   (each position updated by its own window score)
```

This repeats for 50 iterations over 4,000,000 bases. The final state is summarized by counting A/C/G/T frequencies and computing a 64-bit checksum.

---

## hw1_naive.cpp — Step by Step

### 1. `xorshift32(state)` — Random Number Generator
```cpp
uint32_t xorshift32(uint32_t &state) {
    uint32_t x = state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    state = x;
    return x;
}
```
A fast, deterministic pseudo-random number generator. It takes a state, applies three XOR-shift operations, updates the state, and returns the new value. Used to fill the initial sequence reproducibly from a seed.

---

### 2. `fill_sequence(seq, seed)` — Initialize the Sequence
```cpp
void fill_sequence(std::vector<uint8_t> &seq, uint32_t seed) {
    uint32_t s = seed;
    for (size_t i = 0; i < seq.size(); ++i) {
        seq[i] = static_cast<uint8_t>(xorshift32(s) & 0x3u);
    }
}
```
Fills the sequence with values in `{0, 1, 2, 3}` (representing A, C, G, T) by calling `xorshift32` for each position and keeping only the lowest 2 bits (`& 0x3`).

---

### 3. `motif_score_naive(code)` — Score a 5-mer Pattern (THE HOT FUNCTION)
```cpp
int motif_score_naive(uint16_t code) {
    const uint8_t a = code & 0x3;        // base at position i-2
    const uint8_t b = (code >> 2) & 0x3; // base at position i-1
    const uint8_t c = (code >> 4) & 0x3; // base at position i   (center)
    const uint8_t d = (code >> 6) & 0x3; // base at position i+1
    const uint8_t e = (code >> 8) & 0x3; // base at position i+2
    ...
}
```
The `code` is a 10-bit number packing all 5 bases (2 bits each). The function unpacks them and evaluates **7 separate conditional rules**:

| Rule | Condition | Score change |
|---|---|---|
| 1 | `a == c && c == e` (alternating match) | +5 |
| 2 | `b == d` (inner pair match) | +3 |
| 3 | `a+b+c+d+e >= 8` (high-value window) | +2 |
| 4 | `a==0, b==1, c==2, d==3` (ascending motif) | +7 |
| 5 | `a==3, b==2, c==1, d==0` (descending motif) | +7 |
| 6 | `(a==0 && e==3) \|\| (a==3 && e==0)` (edge contrast) | -2 |
| 7 | `(b==0 && d==0) \|\| (b==3 && d==3)` (inner repeat) | -1 |

**Why this is slow:** All 7 conditions depend on the actual base values, which come from a pseudo-random sequence. The CPU's branch predictor cannot learn the pattern — every condition is effectively unpredictable. Result: ~10.72% branch misprediction rate.

---

### 4. `evolve_step_naive(in, out, iteration)` — Main Inner Loop
```cpp
for (int i = 0; i < n; ++i) {
    const int im2 = (i + n - 2) % n;  // circular index: i-2
    const int im1 = (i + n - 1) % n;  // circular index: i-1
    const int ip1 = (i + 1) % n;      // circular index: i+1
    const int ip2 = (i + 2) % n;      // circular index: i+2

    const uint16_t code = in[im2] | (in[im1]<<2) | (in[i]<<4) | (in[ip1]<<6) | (in[ip2]<<8);

    const int score = motif_score_naive(code);
    uint8_t next = (in[i] + (score & 0x3)) & 0x3;

    if (((score ^ iteration ^ i) & 1) != 0)
        next ^= 0x1;

    out[i] = next;
}
```
For every position:
1. Compute **4 modulo operations** for circular indices
2. Load **5 values** from the array (non-contiguous for boundary elements)
3. Pack them into a 10-bit `code`
4. Call `motif_score_naive` → runs all 7 branches
5. Compute the new base value with one final conditional branch
6. Write result to output buffer

**Total per element: 4 modulo ops + 5 loads + 7 unpredictable branches + 1 pack + 1 write.**

---

### 5. `main()` — Program Entry
- Parses `length`, `iterations`, `seed` from command line
- Allocates two buffers `a` and `b` (ping-pong: each iteration reads from one, writes to the other, then swaps)
- Runs `evolve_step_naive` for the requested number of iterations
- Counts A/C/G/T base frequencies
- Prints `RESULT checksum=... A=... C=... G=... T=...` and `TIME_MS ...`

---

## hw1_optimized.cpp — What Changed and Why

The optimized version keeps **identical logic** but restructures the inner loop to eliminate the two main costs: repeated branch evaluation and redundant loads.

---

### Change 1: Precomputed Score LUT

```cpp
std::array<int8_t, 1024> build_score_lut() {
    std::array<int8_t, 1024> lut{};
    for (int code = 0; code < 1024; ++code) {
        lut[code] = static_cast<int8_t>(motif_score_reference(code));
    }
    return lut;
}
```
Since the 5-mer code is 10 bits, there are only `2^10 = 1024` possible values. This function runs **once at startup** and precomputes the score for every possible code into a 1024-entry table.

The table is only **1 KB** in size — it fits entirely in L1 data cache and stays there for the entire run.

**In the hot loop, the 7-branch scoring function is replaced by:**
```cpp
const int score = score_lut[code];  // one array lookup, no branches
```

---

### Change 2: Rolling Encoded Window

**Naive approach** (rebuilds the 5-mer from scratch every step):
```
step i:   loads in[i-2], in[i-1], in[i], in[i+1], in[i+2]  → 5 loads
step i+1: loads in[i-1], in[i],   in[i+1], in[i+2], in[i+3] → 5 loads
```
Four of the five values loaded at step `i` are still needed at step `i+1` — they are loaded twice.

**Optimized approach** (maintains the window incrementally):
```cpp
// Before the loop: build the initial window for i=0
uint16_t code = in[n-2] | (in[n-1]<<2) | (in[0]<<4) | (in[1]<<6) | (in[2]<<8);

// Inside the loop, after computing the result for position i:
const uint8_t incoming = in[(i+3 < n) ? i+3 : i+3-n];
code = (code >> 2) | (incoming << 8);
```

How the roll works:
```
Before: [im2 | im1 | i | ip1 | ip2]  (bits 0-9)
After:  [im1 | i | ip1 | ip2 | new]  (shift right 2 bits, insert new at top)
```
- `code >> 2` drops the oldest base (im2) by shifting it out
- `incoming << 8` places the new base at the top 2 bits (position i+3)

**Result: 1 load per step instead of 5. The 4 modulo operations for circular indices are also eliminated** — only `i+3` needs a bounds check, and it's a simple `< n` comparison instead of `% n`.

---

## Side-by-Side Comparison

```
NAIVE inner loop per element:         OPTIMIZED inner loop per element:
─────────────────────────────         ──────────────────────────────────
compute 4 modulo indices              (none — window maintained by shift)
load in[i-2]                          (already in code register)
load in[i-1]                          (already in code register)
load in[i]                            (already in code register)
load in[i+1]                          (already in code register)
load in[i+2]                          load in[i+3]  ← only NEW base
pack into 16-bit code                 shift + OR   ← single instruction
call motif_score_naive (7 branches)   score_lut[code]  ← one array read
apply score, conditional flip         apply score, conditional flip
write out[i]                          write out[i]
```

---

## Why the 15.7× Speedup Makes Sense

- **Branch misprediction:** 10.72% of 2.4 billion branches mispredicted in the naive version. Each miss costs ~15–20 pipeline flush cycles. Eliminating all scoring branches drops this to 0.01%.
- **Instruction count:** 21.1B → 4.9B instructions (4.3× reduction) from eliminating the redundant loads and modulo operations.
- **Both effects compound:** fewer instructions AND each instruction executes without pipeline stalls.
- **Cache:** the 4 MB sequence fits in L3 cache, and the 1 KB LUT stays in L1. Memory is never the bottleneck.
