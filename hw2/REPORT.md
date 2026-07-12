# HW2 Report — Traditional vs FaaS Hotel Management System

---

## Part 1 — Traditional Architecture

### Design

The Traditional architecture uses a single `HotelSystem` class that **owns all data internally** through private `std::map` members:

```
HotelSystem
├── std::map<int, Guest>              guests_
├── std::map<int, Room>               rooms_
├── std::map<int, Reservation>        reservations_
├── std::map<int, Payment>            payments_
├── std::map<int, CleaningTask>       cleaningTasks_
└── std::map<int, MaintenanceRequest> maintenanceRequests_
```

Operations are **methods** that directly read and mutate the shared private state.

### File structure

```
Traditional/
├── models.h            — shared data structs (Guest, Room, Reservation, ...)
├── hotel_system.h      — HotelSystem class declaration
├── hotel_system.cpp    — all method implementations
├── main.cpp            — demo + benchmark entry point
└── feature_extension.cpp — Part 3 extension demo
```

### 10 Operations

| # | Method | Description |
|---|--------|-------------|
| 1 | `addGuest` | Register a new guest by ID |
| 2 | `addRoom` | Add a room with type, price, floor |
| 3 | `createReservation` | Reserve an available room for a guest |
| 4 | `cancelReservation` | Cancel a non-checked-in reservation |
| 5 | `checkIn` | Mark guest as checked in, room → OCCUPIED |
| 6 | `checkOut` | Check guest out, room → CLEANING |
| 7 | `processPayment` | Record payment for a reservation |
| 8 | `assignCleaningTask` | Assign staff to clean a room → AVAILABLE |
| 9 | `reportMaintenance` | Log maintenance; HIGH/EMERGENCY → room offline |
| 10 | `displayAvailableRooms` | Print available room count |

### Key property

All operations have **O(log n)** access via `std::map::find()`. State is fully encapsulated — no external visibility.

---

## Part 2 — FaaS Architecture

### Design

The FaaS architecture replaces the class with **10 independent stateless functions**. Data lives in an external `HotelStorage` struct passed by reference to every function.

```
                    HotelStorage (external)
                          ▲
                          │ reference
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  add_guest() │  │   check_in() │  │  check_out() │
└──────────────┘  └──────────────┘  └──────────────┘
        ▲                 ▲                 ▲
        │                 │                 │
   AddGuestEvent     CheckInEvent      CheckOutEvent
```

### File structure

```
FaaS/
├── models.h             — same data structs as Traditional
├── storage.h            — HotelStorage struct (external database simulation)
├── storage.cpp          — (minimal, satisfies linker)
├── faas_functions.h     — all 10 event structs + function declarations
├── faas_functions.cpp   — all 10 function implementations
├── main.cpp             — demo + benchmark entry point
└── feature_extension.cpp — Part 3 extension demo
```

### Each function follows this contract

1. Receive a typed **event** (input)
2. Load required data from **external storage**
3. **Validate** the request
4. Perform exactly **one task**
5. **Store** the result back
6. Return and exit

### Key distinction from Traditional

| Property | Traditional | FaaS |
|----------|-------------|------|
| Data ownership | `HotelSystem` owns it (private) | External `HotelStorage` passed in |
| Lookup method | `std::map::find()` — O(log n) | Linear scan over `std::vector` — O(n) |
| State between calls | Persistent inside the class | No state; storage is always external |
| Adding a feature | Must modify the class | Add a new function, existing code untouched |

---

## Part 3 — Feature Extension: Emergency Maintenance + Auto Reassignment

### Scenario

```
Guest Alice is in Room 101
            │
            ▼
Pipe burst reported — EMERGENCY
            │
            ▼
Room 101 → MAINTENANCE (unavailable)
            │
            ▼
Find active reservation for Room 101
            │
            ▼
Find available Room 102 (same type)
            │
            ▼
Move reservation: Room 101 → Room 102
            │
            ▼
Notify Alice: "Your room is now 102"
```

---

### Traditional — implementation cost

To add this feature we had to **modify existing files**:

- `hotel_system.h` — added `emergencyMaintenance()` declaration
- `hotel_system.cpp` — added `emergencyMaintenance()` implementation

The method directly accesses **three private members** in one function:

```cpp
bool HotelSystem::emergencyMaintenance(int requestId, int roomId,
                                        const std::string& issue) {
    // Step 1: access rooms_          ← private
    // Step 2: search reservations_   ← private
    // Step 3: search rooms_ again    ← private
    // Step 4: modify reservations_   ← private
    // Step 5: access guests_         ← private
}
```

**Problem**: `emergencyMaintenance()` is responsible for:
- Maintenance reporting
- Reservation search
- Room availability search
- Reservation reassignment
- Guest notification

This violates Single Responsibility and shows **tight coupling**: every new cross-cutting feature must be added to the `HotelSystem` class, which keeps growing.

---

### FaaS — implementation cost

To add this feature we **only added new code** inside `feature_extension.cpp`:

```
find_affected_reservations()   ← new function
find_replacement_room()        ← new function
reassign_reservation()         ← new function
notify_guest()                 ← new function
emergency_chain()              ← orchestrator
```

**Zero changes to existing files.** `faas_functions.cpp` was not touched.

The flow is explicit and composable:

```
report_maintenance  →  find_affected_reservations  →  find_replacement_room
                                                              │
                                               reassign_reservation  →  notify_guest
```

**Trade-off**:
- ✓ Existing code is untouched — no regression risk
- ✓ Each step is independently testable
- ✗ A failure between steps leaves storage in a partial state (no atomicity)
- ✗ Understanding the full flow requires reading multiple functions

---

## Part 4 — Performance Evaluation

### Benchmark workload (identical for both)

| Phase | Operations |
|-------|-----------|
| Add guests | 10,000 |
| Add rooms | 1,000 |
| Create reservations (10 rounds × 1,000) | 10,000 |
| Check-ins | 10,000 |
| Process payments | 10,000 |
| Check-outs | 10,000 |
| Assign cleaning tasks | 10,000 |
| Report maintenance requests | 5,000 |
| **Total** | **~66,000 operations** |

Both binaries compiled with: `g++ -O2 -std=c++17 -g`

---

### Results

| Metric | Traditional | FaaS | Ratio |
|--------|-------------|------|-------|
| Elapsed time | 0.0211 s | 0.5971 s | **FaaS 28× slower** |
| CPU cycles | 45,507,954 | 1,419,352,888 | **31× more** |
| Instructions | 64,419,929 | 1,627,120,203 | **25× more** |
| Cache-misses | 92 | 93 | equal |
| Context-switches | 3 | 13 | ~4× more |
| Max RSS memory | 8,268 KB | 5,460 KB | **FaaS uses 34% less** |

*(5-run average via `perf stat -r 5`)*

---

### Analysis

#### Why FaaS is 28× slower

The dominant cost is **algorithmic**, not architectural.

- **Traditional** uses `std::map<int, T>`: every `checkIn`, `checkOut`, `createReservation` does one `map::find()` call — **O(log n)** with n ≤ 10,000.
- **FaaS** uses `std::vector<T>`: every function scans the entire vector for a matching ID — **O(n)**. By round 10, the reservations vector holds 10,000 entries; finding one requires scanning ~5,000 entries on average.

Total extra comparisons for check-in alone across 10 rounds:

$$\sum_{r=0}^{9} 1000 \times \frac{(r+1) \times 1000}{2} \approx 27.5 \text{ million comparisons}$$

This matches the 25× instruction count difference.

> In a real FaaS deployment this cost would not exist — cloud functions use indexed databases (DynamoDB, Firestore) with O(1) key lookups. The simulation with `std::vector` honestly represents the *overhead of external storage access*, not a flaw in FaaS design.

#### Why cache-misses are equal

Both implementations fit entirely in L2/L3 cache (≤ 10 MB). The bottleneck is instruction count, not memory latency. Neither architecture benefits from or suffers from cache effects at this workload scale.

#### Why FaaS uses less memory

`std::vector` stores objects **contiguously** in one allocation.  
`std::map` allocates a **heap node per entry** (red-black tree) with three pointers overhead per node (~24 bytes extra per entry). With 10,000 map entries across 6 maps, the Traditional binary uses ~2.8 MB more in tree node overhead.

#### Context-switches

FaaS has 4× more context-switches (13 vs 3). These come from the OS scheduler interrupting the longer-running process. Traditional finishes in 21 ms — too fast for the scheduler to intervene.

---

### Summary table

| Property | Traditional wins | FaaS wins |
|----------|-----------------|-----------|
| Speed | ✓ 28× faster | |
| Instructions | ✓ 25× fewer | |
| Memory footprint | | ✓ 34% smaller |
| Adding new features | | ✓ No class modification |
| Testability of individual ops | | ✓ Fully isolated functions |
| Data consistency (atomicity) | ✓ Single method | |

---

## Conclusion

The Traditional architecture is significantly faster for this workload because its in-process `std::map` provides O(log n) indexed lookups, while the FaaS simulation uses O(n) linear scans to mimic external storage queries.

In a real cloud environment, this difference would be reversed in some dimensions: FaaS functions scale horizontally (each invocation is independent), and indexed cloud databases restore O(1) lookups. The Traditional monolith would become the bottleneck once it cannot fit on one machine.

The feature extension experiment confirms the architectural trade-off clearly:
- **Traditional**: adding one complex feature required modifying 2 existing files and growing the class with a method that touches 3 private data structures.
- **FaaS**: adding the same feature required 0 changes to existing files; all new logic was isolated in new functions.
