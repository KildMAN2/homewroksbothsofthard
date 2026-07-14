# HW2 — Traditional Software Design vs Function-as-a-Service

**System scenario:** Hotel Management System | **Language:** C++ (`-O2 -std=c++17`)
**Student:** Sari Mansour — 322449539

Both architectures implement the **same 10 operations** over the same data model
(`Guest`, `Room`, `Reservation`, `Payment`, `CleaningTask`, `MaintenanceRequest`).

| # | Operation | Description |
|---|-----------|-------------|
| 1 | add_guest | Register a guest by ID |
| 2 | add_room | Add a room (type, price, floor) |
| 3 | create_reservation | Reserve an available room for a guest |
| 4 | cancel_reservation | Cancel a non-checked-in reservation |
| 5 | check_in | Check guest in -> room OCCUPIED |
| 6 | check_out | Check guest out -> room CLEANING |
| 7 | process_payment | Record a payment for a reservation |
| 8 | assign_cleaning_task | Assign staff to clean -> room AVAILABLE |
| 9 | report_maintenance | Log maintenance; HIGH/EMERGENCY takes room offline |
| 10 | display_available_rooms | Report available room count |

---

## Part 1 — Traditional Architecture

A single `HotelSystem` **class owns all data internally** through private `std::map`
members; operations are **methods** that directly read and mutate this shared state.

```
class HotelSystem {                     Files:
  private:                                models.h          (data structs)
    map<int,Guest>       guests_;         hotel_system.h    (class declaration)
    map<int,Room>        rooms_;          hotel_system.cpp  (method bodies)
    map<int,Reservation> reservations_;   main.cpp          (demo + benchmark)
    ... payments_, cleaningTasks_,        feature_extension.cpp (Part 3)
        maintenanceRequests_
```

**Key property:** every lookup uses `std::map::find()` -> **O(log n)**. State is fully
encapsulated with no external visibility.

---

## Part 2 — Function-as-a-Service Architecture

The class is replaced by **10 independent, stateless functions**. There are no private
members; data lives in an **external** `HotelStorage` struct (a `std::map`, same indexed
store as Traditional) passed by reference. Each function receives a generic **event
payload** — a `std::map<string,string>`, modeling the JSON body a real cloud platform
(AWS Lambda / Azure Functions) delivers to a handler — parses the fields it needs,
validates, performs one task, and returns a serialized result. Invocation goes through a
`FaaSOrchestrator` that looks handlers up **by name** and calls them indirectly via
`std::function`, mirroring how an API Gateway routes an event to the registered handler.

```
            FaaSOrchestrator (name -> handler registry)
                        |  invoke("check_in", event, storage)
                        v
              HotelStorage (external "database", std::map)
                        ^  passed by reference
        +---------------+---------------+
   add_guest(e,s)   check_in(e,s)   check_out(e,s)   ... 10 handlers
        ^               ^               ^
  EventData{"id":"1", EventData{"reservationId":"1"}  ...
   "name":"Alice",...}

Files: models.h, storage.h (HotelStorage), faas_functions.h (EventData/ResultData,
       FaaSOrchestrator, handler decls), faas_functions.cpp (10 handlers + orchestrator),
       main.cpp, feature_extension.cpp
```

### How the two architectures differ

| Property | Traditional | FaaS |
|----------|-------------|------|
| Data ownership | `HotelSystem` owns it (private) | External `HotelStorage` passed in |
| Storage lookup | `map::find()` — O(log n) | `map::find()` — O(log n) (same store) |
| Invocation | direct method call | name lookup + `std::function` dispatch |
| Argument passing | typed C++ parameters | generic string payload (marshal/parse) |
| State between calls | persists in the object | none; storage is always external |
| Adding a feature | modify the class | add a function; existing code untouched |

Both use the same indexed storage, so the benchmark isolates the cost of the **FaaS
invocation model** (marshaling + routing) rather than a data-structure difference. Both
are stateless *between program runs*; FaaS is additionally stateless *between calls*,
which is what lets a real cloud platform scale each function independently.

---

## Part 3 — Feature Extension: Emergency Maintenance + Auto Room Reassignment

**New feature:** when an emergency maintenance issue is reported, the affected room is
taken offline, any active reservation is moved to a free room of the same type, and the
guest is notified.

```
report emergency -> room OFFLINE -> find affected reservation
      -> find replacement room (same type) -> reassign -> notify guest
```

**Traditional — must modify existing files.** A new method `emergencyMaintenance()` was
added to `hotel_system.h` *and* `hotel_system.cpp`. One method now touches **three
private members** (`rooms_`, `reservations_`, `guests_`) and mixes five responsibilities
(report, search reservations, search rooms, reassign, notify). This increases coupling —
the class grows with every cross-cutting feature and the change risks breaking existing
behaviour because it edits shared code.

**FaaS — only new files/functions added.** The same feature was implemented in
`feature_extension.cpp` as four new independent functions
(`find_affected_reservations`, `find_replacement_room`, `reassign_reservation`,
`notify_guest`) plus an orchestrator that chains them. **Zero existing functions were
modified**, so there is no regression risk and each new function is independently
testable.

| | Traditional | FaaS |
|---|---|---|
| Files changed | 2 existing files edited | 0 existing; 1 new file |
| Responsibilities added to old code | 5 (in one method) | 0 |
| Regression risk | Medium (shared class edited) | Low (isolated additions) |
| Debugging the full flow | Easy (one call stack) | Harder (multi-step, no atomicity) |

**Verdict:** FaaS is clearly easier to *extend*; Traditional is easier to *debug and keep
consistent* because the whole flow is one atomic method.

---

## Part 4 — Performance Evaluation

**Workload (identical for both, `benchmark` mode, ~66,000 operations):**
10,000 guests, 1,000 rooms, 10,000 reservations, 10,000 check-ins, 10,000 payments,
10,000 check-outs, 10,000 cleaning tasks, 5,000 maintenance reports.

Measured on the course KVM (Ubuntu, `perf stat -r 5`, `/usr/bin/time`). Both
implementations use the same indexed `std::map` storage, so this experiment isolates the
cost of the **FaaS invocation model** (event marshaling + name-based dispatch) rather
than a data-structure artifact.

| Metric | Traditional | FaaS | Result |
|--------|-------------|------|--------|
| Execution time | **0.0216 s** | 0.0580 s | FaaS 2.7x slower |
| CPU cycles | **45.6 M** | 136.0 M | FaaS 3.0x more |
| Instructions | **64.4 M** | 292.9 M | FaaS 4.5x more |
| Instructions/cycle | 1.37 | 2.15 | FaaS higher (simpler, linear parsing code) |
| Cache-misses | 71 | 33 | both negligible, within noise |
| Context-switches | 3 | 7 | FaaS more (longer runtime) |
| Max memory (RSS) | 8,224 KB | 8,644 KB | FaaS +5% |

**Which performed better and why.** **Traditional is faster**, by about **2.7x** in wall
time and **3x** in CPU cycles. Because both versions use identical `std::map` storage,
none of this gap comes from the data structure — it is the **pure cost of the FaaS
invocation model**:

- **Event marshaling.** Every call builds a `std::map<string,string>` and converts each
  argument with `std::to_string`; every handler parses it back with `std::stoi`/`std::stod`.
  This happens for every one of the ~66,000 operations and is the dominant cost — it
  explains why FaaS needs **4.5x more instructions** for the same logical work.
- **Name-based dispatch.** `FaaSOrchestrator::invoke()` performs a `std::string` key
  lookup in a `std::map<string, std::function<...>>` and then an indirect call through
  `std::function`, versus a direct (often inlined) method call in Traditional.
- **Higher IPC (2.15 vs 1.37) despite more instructions.** String parsing/formatting is
  simple, branch-light, sequential code that the CPU pipelines well — it is *more*
  instructions, but each one is cheap, so cycles grow slower (3x) than instructions (4.5x).
- **Cache-misses are negligible for both** (71 vs 33) — the working set fits in cache;
  the bottleneck is instruction count from marshaling, not memory latency.
- **Memory is nearly identical (+5% for FaaS)** — the extra allocations are the small,
  transient event/result maps, which are freed immediately after each call.

**Interpretation.** This is a fair, apples-to-apples measurement of the real trade-off:
FaaS's stateless, event-driven contract has a genuine per-call tax (marshaling +
routing) even in a best-case, all-in-process simulation. In an actual cloud deployment
this tax is dwarfed by network latency and cold starts, so the *relative* overhead shown
here (2.7-4.5x) is a conservative lower bound on what FaaS costs per invocation versus an
in-process call — while still buying stateless, independently scalable, easily replaceable
functions.

---

## Conclusion

The two implementations are functionally identical but structurally opposite.
Traditional wins on raw single-machine performance (2.7x faster wall time, 3x fewer
cycles), because a direct method call over in-process state has zero marshaling or
routing cost. FaaS wins on extensibility — the Part 3 feature needed **zero** changes to
existing FaaS code, versus editing two Traditional files — and its stateless, event-driven
contract is what allows independent deployment and horizontal scaling in a real cloud
environment. The measurements confirm the standard architectural trade-off: monoliths are
faster and simpler in-process, while FaaS trades a measurable per-call tax (event
marshaling + name-based dispatch) for isolation, independent scaling, and low-risk
evolution.

---

### Appendix — AI Tool Usage

An AI assistant (GitHub Copilot) was used only for **architectural discussion and code
organization**: brainstorming the Part-3 room-reassignment feature, structuring the code
into the multi-file layout, and helping interpret the `perf` output. The scenario choice,
benchmark design, final code, and all written analysis were decided and verified by the
student. No external repository implementation was copied.