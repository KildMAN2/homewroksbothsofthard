// Part 3 -- Feature Extension: Emergency Maintenance + Auto Room Reassignment
//
// FaaS Architecture Analysis:
//   To add this feature we ONLY added NEW files:
//     faas_functions.h  <- unchanged
//     faas_functions.cpp <- unchanged
//   All new logic lives in this file as independent static functions.
//   Zero changes to existing code.
//
// Trade-off:
//   + Existing functions untouched (zero regression risk)
//   + Each new function has one responsibility and is independently testable
//   - A failure between steps leaves storage in a partial state
//   - The full flow requires reading multiple files to understand

#include <iostream>
#include <vector>
#include "faas_functions.h"

// ─── New extension functions (no existing files modified) ─────────────────────

static std::vector<int> find_affected_reservations(int roomId,
                                                    const HotelStorage& s) {
    std::vector<int> result;
    for (const Reservation& res : s.reservations)
        if (res.roomId == roomId && res.active)
            result.push_back(res.id);
    return result;
}

static int find_replacement_room(RoomType needed, int excludeId,
                                  const HotelStorage& s) {
    for (const Room& r : s.rooms)
        if (r.id != excludeId && r.type == needed && r.status == RoomStatus::AVAILABLE)
            return r.id;
    return -1;
}

static bool reassign_reservation(int resId, int newRoomId, HotelStorage& s) {
    for (Reservation& res : s.reservations) {
        if (res.id == resId && res.active) {
            res.roomId = newRoomId;
            for (Room& r : s.rooms)
                if (r.id == newRoomId) { r.status = RoomStatus::RESERVED; break; }
            return true;
        }
    }
    return false;
}

static void notify_guest(int guestId, const std::string& msg,
                          const HotelStorage& s) {
    for (const Guest& g : s.guests)
        if (g.id == guestId) {
            std::cout << "  [notify_guest] SMS to " << g.name
                      << " (" << g.phone << "): " << msg << "\n";
            return;
        }
}

// Orchestrator: calls the chain of independent functions
static void emergency_chain(int requestId, int roomId,
                             const std::string& issue, HotelStorage& s) {
    std::cout << "[FaaS chain] EMERGENCY room " << roomId << ": " << issue << "\n";

    // Step 1: use existing report_maintenance (unmodified)
    report_maintenance({requestId, roomId, issue, "EMERGENCY"}, s);
    std::cout << "  [report_maintenance] Room " << roomId << " -> MAINTENANCE\n";

    // Step 2: new function
    auto affected = find_affected_reservations(roomId, s);
    std::cout << "  [find_affected_reservations] " << affected.size()
              << " reservation(s) affected\n";

    for (int resId : affected) {
        int guestId = -1;
        RoomType rtype = RoomType::SINGLE;
        for (const Reservation& r : s.reservations)
            if (r.id == resId) { guestId = r.guestId; break; }
        for (const Room& r : s.rooms)
            if (r.id == roomId) { rtype = r.type; break; }

        // Step 3: new function
        int newRoom = find_replacement_room(rtype, roomId, s);
        if (newRoom == -1) {
            std::cout << "  [find_replacement_room] No replacement for Res #" << resId << "\n";
            continue;
        }
        std::cout << "  [find_replacement_room] Replacement: Room " << newRoom << "\n";

        // Step 4: new function
        reassign_reservation(resId, newRoom, s);
        std::cout << "  [reassign_reservation] Res #" << resId
                  << ": Room " << roomId << " -> Room " << newRoom << "\n";

        // Step 5: new function
        if (guestId != -1)
            notify_guest(guestId,
                "Your room has been changed to room " + std::to_string(newRoom) +
                " due to an emergency.", s);
    }
}

int main() {
    std::cout << "===== FaaS: Part 3 Feature Extension Demo =====\n\n";
    std::cout << "Feature: Emergency Maintenance + Automatic Room Reassignment\n";
    std::cout << "Cost: 0 existing files modified. 4 new functions added here.\n\n";

    HotelStorage s;
    add_guest({1, "Alice Johnson", "555-1001"}, s);
    add_guest({2, "Bob Martinez",  "555-1002"}, s);
    add_room({101, RoomType::SINGLE, 80.0,  1}, s);
    add_room({102, RoomType::SINGLE, 80.0,  1}, s);   // replacement
    add_room({201, RoomType::DOUBLE, 140.0, 2}, s);
    create_reservation({1, 1, 101, "2024-06-01", "2024-06-05"}, s);
    create_reservation({2, 2, 201, "2024-06-01", "2024-06-03"}, s);
    check_in({1}, s);
    check_in({2}, s);

    std::cout << "Initial state:\n";
    display_available_rooms(s);

    std::cout << "\n--- Emergency: Pipe burst in Room 101 ---\n";
    emergency_chain(1, 101, "Pipe burst -- water leak", s);

    std::cout << "\nState after emergency:\n";
    display_available_rooms(s);

    std::cout << "\n===== Extension Demo Complete =====\n";
    return 0;
}
