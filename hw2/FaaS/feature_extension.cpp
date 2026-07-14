// Part 3 -- Feature Extension: Emergency Maintenance + Auto Room Reassignment
//
// FaaS Architecture Analysis:
//   To add this feature we ONLY added NEW functions in this file:
//     faas_functions.h   <- unchanged
//     faas_functions.cpp <- unchanged
//   All new logic lives here as independent functions. Zero changes to
//   existing code.
//
// Trade-off:
//   + Existing functions untouched (zero regression risk)
//   + Each new function has one responsibility and is independently testable
//   - A failure between steps leaves storage in a partial state (no atomicity)
//   - The full flow requires reading multiple functions to understand

#include <iostream>
#include <vector>
#include "faas_functions.h"

// ─── New extension functions (no existing files modified) ─────────────────────

static std::vector<int> find_affected_reservations(int roomId,
                                                    const HotelStorage& s) {
    std::vector<int> result;
    for (const auto& kv : s.reservations)
        if (kv.second.roomId == roomId && kv.second.active)
            result.push_back(kv.second.id);
    return result;
}

static int find_replacement_room(RoomType needed, int excludeId,
                                  const HotelStorage& s) {
    for (const auto& kv : s.rooms)
        if (kv.first != excludeId && kv.second.type == needed &&
            kv.second.status == RoomStatus::AVAILABLE)
            return kv.first;
    return -1;
}

static bool reassign_reservation(int resId, int newRoomId, HotelStorage& s) {
    auto it = s.reservations.find(resId);
    if (it == s.reservations.end() || !it->second.active) return false;
    it->second.roomId = newRoomId;
    auto rit = s.rooms.find(newRoomId);
    if (rit != s.rooms.end()) rit->second.status = RoomStatus::RESERVED;
    return true;
}

static void notify_guest(int guestId, const std::string& msg,
                          const HotelStorage& s) {
    auto it = s.guests.find(guestId);
    if (it != s.guests.end())
        std::cout << "  [notify_guest] SMS to " << it->second.name
                  << " (" << it->second.phone << "): " << msg << "\n";
}

// Chains the independent functions/handlers for this feature
static void emergency_chain(FaaSOrchestrator& orch, int requestId, int roomId,
                             const std::string& issue, HotelStorage& s) {
    std::cout << "[FaaS chain] EMERGENCY room " << roomId << ": " << issue << "\n";

    // Step 1: reuse existing report_maintenance handler (unmodified) via the
    // same event-dispatch path used for every other operation.
    orch.invoke("report_maintenance",
        {{"id", std::to_string(requestId)}, {"roomId", std::to_string(roomId)},
         {"description", issue}, {"priority", "EMERGENCY"}}, s);
    std::cout << "  [report_maintenance] Room " << roomId << " -> MAINTENANCE\n";

    // Step 2: new function
    auto affected = find_affected_reservations(roomId, s);
    std::cout << "  [find_affected_reservations] " << affected.size()
              << " reservation(s) affected\n";

    RoomType rtype = RoomType::SINGLE;
    auto roomIt = s.rooms.find(roomId);
    if (roomIt != s.rooms.end()) rtype = roomIt->second.type;

    for (int resId : affected) {
        int guestId = -1;
        auto rIt = s.reservations.find(resId);
        if (rIt != s.reservations.end()) guestId = rIt->second.guestId;

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
    FaaSOrchestrator orch;
    orch.registerFunction("add_guest", add_guest);
    orch.registerFunction("add_room", add_room);
    orch.registerFunction("create_reservation", create_reservation);
    orch.registerFunction("check_in", check_in);
    orch.registerFunction("report_maintenance", report_maintenance);
    orch.registerFunction("display_available_rooms", display_available_rooms);

    orch.invoke("add_guest", {{"id","1"},{"name","Alice Johnson"},{"phone","555-1001"}}, s);
    orch.invoke("add_guest", {{"id","2"},{"name","Bob Martinez"},{"phone","555-1002"}}, s);
    orch.invoke("add_room", {{"id","101"},{"type","SINGLE"},{"price","80.0"},{"floor","1"}}, s);
    orch.invoke("add_room", {{"id","102"},{"type","SINGLE"},{"price","80.0"},{"floor","1"}}, s); // replacement
    orch.invoke("add_room", {{"id","201"},{"type","DOUBLE"},{"price","140.0"},{"floor","2"}}, s);
    orch.invoke("create_reservation", {{"id","1"},{"guestId","1"},{"roomId","101"},{"checkIn","2024-06-01"},{"checkOut","2024-06-05"}}, s);
    orch.invoke("create_reservation", {{"id","2"},{"guestId","2"},{"roomId","201"},{"checkIn","2024-06-01"},{"checkOut","2024-06-03"}}, s);
    orch.invoke("check_in", {{"reservationId","1"}}, s);
    orch.invoke("check_in", {{"reservationId","2"}}, s);

    std::cout << "Initial state:\n";
    orch.invoke("display_available_rooms", {}, s);

    std::cout << "\n--- Emergency: Pipe burst in Room 101 ---\n";
    emergency_chain(orch, 1, 101, "Pipe burst -- water leak", s);

    std::cout << "\nState after emergency:\n";
    orch.invoke("display_available_rooms", {}, s);

    std::cout << "\n===== Extension Demo Complete =====\n";
    return 0;
}
