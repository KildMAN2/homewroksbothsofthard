/*
 * Part 3 — Feature Extension: Dynamic Room Pricing
 *
 * New feature: adjust room prices based on current occupancy.
 * If occupancy > 80% → surge pricing (+30%)
 * If occupancy < 30% → discount pricing (-20%)
 *
 * FaaS ARCHITECTURE — Extension Analysis
 * ────────────────────────────────────────
 * To add this feature in the FaaS design:
 *
 *  RISK:  Low
 *  EFFORT: Add ONE new standalone function — nothing else changes.
 *    1. Write apply_dynamic_pricing() as an isolated stateless function
 *    2. Register it in the orchestrator
 *    3. Trigger it after check_in_guest or check_out_guest events
 *
 *  ADVANTAGE: The new function reads occupancy from the store and writes
 *  updated prices back. It has zero dependency on any other function's
 *  internals. Existing functions are completely untouched.
 *  It can be tested and deployed in isolation.
 *
 * This file is a standalone compilable demo of just the new function.
 */

#include <iostream>
#include <string>
#include <map>
#include <functional>
#include <algorithm>

using EventData  = std::map<std::string, std::string>;
using ResultData = std::map<std::string, std::string>;

// Shared store (same external store used by all FaaS functions)
static std::map<std::string, std::string> store;

static std::string storeGet(const std::string& key, const std::string& def = "") {
    return store.count(key) ? store.at(key) : def;
}

// ── NEW function: apply_dynamic_pricing ───────────────────────────────────────
// Completely independent — reads occupancy from store, writes prices back.
// No other function needs to change.
ResultData applyDynamicPricing(const EventData& /*ev*/) {
    ResultData res;

    // Count occupied/reserved rooms
    int total = 0, occupied = 0;
    for (auto& kv : store) {
        if (kv.first.size() > 5 &&
            kv.first.substr(0, 5) == "room." &&
            kv.first.find(".status") != std::string::npos) {
            total++;
            if (kv.second == "OCCUPIED" || kv.second == "RESERVED")
                occupied++;
        }
    }

    double rate       = total > 0 ? (double)occupied / total : 0.0;
    double multiplier = 1.0;
    if      (rate > 0.80) multiplier = 1.30;
    else if (rate < 0.30) multiplier = 0.80;

    // Update prices for each room independently
    for (auto& kv : store) {
        if (kv.first.size() > 5 &&
            kv.first.substr(0, 5) == "room." &&
            kv.first.find(".price") != std::string::npos &&
            kv.first.find(".adj")   == std::string::npos) {
            double base    = std::stod(kv.second);
            double adjusted = base * multiplier;
            // Write adjusted price as a separate key — base price untouched
            std::string rid = kv.first.substr(5,
                              kv.first.find(".price") - 5);
            store["room." + rid + ".adj_price"] = std::to_string(adjusted);
        }
    }

    res["status"]     = "OK";
    res["occupancy"]  = std::to_string((int)(rate * 100));
    res["multiplier"] = std::to_string(multiplier);
    res["message"]    = "Dynamic pricing applied — occupancy "
                        + std::to_string((int)(rate * 100))
                        + "%, multiplier x" + std::to_string(multiplier);
    std::cout << "[apply_dynamic_pricing] " << res["message"] << "\n";
    return res;
}

// ── Demonstration ─────────────────────────────────────────────────────────────

int main() {
    std::cout << "=== Feature Extension Demo: Dynamic Pricing (FaaS) ===\n\n";

    // Simulate store state (as if check_in_guest already ran for 5/6 rooms)
    store["room.101.status"] = "OCCUPIED"; store["room.101.price"] = "80";
    store["room.102.status"] = "OCCUPIED"; store["room.102.price"] = "80";
    store["room.201.status"] = "OCCUPIED"; store["room.201.price"] = "140";
    store["room.202.status"] = "OCCUPIED"; store["room.202.price"] = "140";
    store["room.301.status"] = "OCCUPIED"; store["room.301.price"] = "300";
    store["room.302.status"] = "AVAILABLE";store["room.302.price"] = "300";
    // Occupancy = 5/6 = 83% -> surge pricing

    applyDynamicPricing({});

    std::cout << "\nAdjusted prices (base -> adjusted):\n";
    for (auto& kv : store) {
        if (kv.first.find(".adj_price") != std::string::npos) {
            std::string rid = kv.first.substr(5,
                              kv.first.find(".adj_price") - 5);
            std::cout << "  Room " << rid
                      << ": $" << storeGet("room." + rid + ".price")
                      << " -> $" << kv.second << "\n";
        }
    }

    std::cout << "\nChanges required in the FaaS architecture:\n"
              << "  1. Write apply_dynamic_pricing() — ONE new file/function\n"
              << "  2. Register it in the orchestrator\n"
              << "  3. Trigger it as a downstream event after check_in/check_out\n"
              << "\n"
              << "Risk: Low — zero changes to any existing function.\n"
              << "A bug in pricing cannot corrupt check-in or reservation logic.\n"
              << "The function can be tested, deployed, and rolled back independently.\n";

    return 0;
}
