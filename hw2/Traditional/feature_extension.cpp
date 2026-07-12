/*
 * Part 3 — Feature Extension: Dynamic Room Pricing
 *
 * New feature: adjust room prices automatically based on current occupancy.
 * If occupancy > 80% → surge pricing (+30%)
 * If occupancy < 30% → discount pricing (-20%)
 *
 * TRADITIONAL ARCHITECTURE — Extension Analysis
 * ──────────────────────────────────────────────
 * To add this feature in the traditional monolithic design:
 *
 *  RISK:  Medium-High
 *  EFFORT: Must modify the central HotelSystem class:
 *    1. Add pricePerNight field to Room struct (or the class)
 *    2. Add calculateOccupancyRate() — reads from the rooms map (shared state)
 *    3. Add applyDynamicPricing()    — iterates and mutates all Room prices
 *    4. Call applyDynamicPricing() inside checkInGuest() and checkOutGuest()
 *       so prices update whenever occupancy changes
 *    5. Update generateDailyReport() to show adjusted prices
 *
 *  PROBLEM: The pricing logic is tightly coupled to the room reservation and
 *  check-in logic. A bug in pricing could corrupt room state or trigger
 *  infinite updates. Testing requires spinning up the full HotelSystem.
 *
 * This file shows the partial implementation of the extension in isolation.
 * In a real project this code would be merged into HotelSystem in main.cpp.
 */

#include <iostream>
#include <map>
#include <string>
#include <vector>

// ── Simulated cut-down Room/HotelSystem to show the diff ─────────────────────

struct Room {
    int         id;
    std::string status;     // AVAILABLE, OCCUPIED, RESERVED, CLEANING, MAINTENANCE
    double      basePrice;
    double      currentPrice;
};

class HotelSystem {
public:
    // ... all existing methods from main.cpp ...

    // ── NEW: calculate occupancy rate ─────────────────────────────────────
    // Requires access to the entire rooms map (shared state dependency)
    double calculateOccupancyRate() const {
        if (rooms.empty()) return 0.0;
        int occupied = 0;
        for (const auto& kv : rooms) {
            if (kv.second.status == "OCCUPIED" ||
                kv.second.status == "RESERVED")
                occupied++;
        }
        return (double)occupied / rooms.size();
    }

    // ── NEW: apply dynamic pricing ────────────────────────────────────────
    // MUST iterate and mutate every room — touching shared state widely.
    // Called from checkInGuest() and checkOutGuest() after state changes.
    void applyDynamicPricing() {
        double rate = calculateOccupancyRate();
        double multiplier = 1.0;

        if (rate > 0.80)      multiplier = 1.30;   // surge: +30%
        else if (rate < 0.30) multiplier = 0.80;   // discount: -20%

        for (auto& kv : rooms) {
            kv.second.currentPrice = kv.second.basePrice * multiplier;
        }

        std::cout << "[PRICING] Occupancy: " << (int)(rate * 100)
                  << "% — multiplier: x" << multiplier << "\n";
        for (const auto& kv : rooms) {
            std::cout << "  Room " << kv.first
                      << ": $" << kv.second.basePrice
                      << " -> $" << kv.second.currentPrice << "\n";
        }
    }

    // checkInGuest() would need to call applyDynamicPricing() at the end.
    // checkOutGuest() would also need to call applyDynamicPricing() at the end.
    // Both methods in main.cpp must be modified.

private:
    std::map<int, Room> rooms;   // shared mutable state
};

// ── Demonstration ─────────────────────────────────────────────────────────────

int main() {
    std::cout << "=== Feature Extension Demo: Dynamic Pricing (Traditional) ===\n\n";

    // Simulate a partially filled hotel
    HotelSystem hotel;
    // (In the real integration, hotel would be initialised from initializeHotel()
    //  and the rooms map would already be populated.)

    std::cout << "Changes required in the TRADITIONAL architecture:\n"
              << "  1. Room struct: add currentPrice field\n"
              << "  2. HotelSystem: add calculateOccupancyRate()\n"
              << "  3. HotelSystem: add applyDynamicPricing()\n"
              << "  4. checkInGuest()  — add applyDynamicPricing() call at end\n"
              << "  5. checkOutGuest() — add applyDynamicPricing() call at end\n"
              << "  6. generateDailyReport() — show currentPrice instead of basePrice\n"
              << "\n"
              << "Risk: Medium — touches 4 existing methods + 1 struct.\n"
              << "Any error in applyDynamicPricing() could corrupt prices for\n"
              << "all rooms simultaneously because all state lives in one object.\n";

    return 0;
}
