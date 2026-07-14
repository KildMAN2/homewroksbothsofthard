#include "faas_functions.h"
#include <iostream>

// ─────────────────────────────────────────────────────────────────────────────
// FaaS Hotel Management System -- 10 independent function handlers
//
// Each handler follows the real FaaS contract:
//   1. Receive a generic event payload (string key/value pairs, like JSON)
//   2. Parse/marshal the fields it needs
//   3. Load required data from external storage
//   4. Validate the request
//   5. Perform exactly ONE task
//   6. Store the result, return a serialized result payload
//
// Handlers are stateless and own no data; HotelStorage is always external.
// ─────────────────────────────────────────────────────────────────────────────

static RoomType parseRoomType(const std::string& t) {
    if (t == "DOUBLE") return RoomType::DOUBLE;
    if (t == "SUITE")  return RoomType::SUITE;
    return RoomType::SINGLE;
}

// 1. add_guest
ResultData add_guest(const EventData& e, HotelStorage& s) {
    int id = std::stoi(e.at("id"));
    if (s.guests.count(id)) return {{"success", "false"}, {"reason", "duplicate"}};
    s.guests[id] = {id, e.at("name"), e.at("phone")};
    return {{"success", "true"}};
}

// 2. add_room
ResultData add_room(const EventData& e, HotelStorage& s) {
    int id = std::stoi(e.at("id"));
    if (s.rooms.count(id)) return {{"success", "false"}, {"reason", "duplicate"}};
    RoomType type = parseRoomType(e.at("type"));
    double price  = std::stod(e.at("price"));
    int floor     = std::stoi(e.at("floor"));
    s.rooms[id] = {id, type, RoomStatus::AVAILABLE, price, floor};
    return {{"success", "true"}};
}

// 3. create_reservation
ResultData create_reservation(const EventData& e, HotelStorage& s) {
    int id      = std::stoi(e.at("id"));
    int guestId = std::stoi(e.at("guestId"));
    int roomId  = std::stoi(e.at("roomId"));

    if (!s.guests.count(guestId)) return {{"success", "false"}, {"reason", "no_guest"}};
    auto rit = s.rooms.find(roomId);
    if (rit == s.rooms.end() || rit->second.status != RoomStatus::AVAILABLE)
        return {{"success", "false"}, {"reason", "room_unavailable"}};

    s.reservations[id] = {id, guestId, roomId, e.at("checkIn"), e.at("checkOut"), true, false};
    rit->second.status = RoomStatus::RESERVED;
    return {{"success", "true"}};
}

// 4. cancel_reservation
ResultData cancel_reservation(const EventData& e, HotelStorage& s) {
    int resId = std::stoi(e.at("reservationId"));
    auto it = s.reservations.find(resId);
    if (it == s.reservations.end() || !it->second.active || it->second.checkedIn)
        return {{"success", "false"}};
    it->second.active = false;
    auto rit = s.rooms.find(it->second.roomId);
    if (rit != s.rooms.end()) rit->second.status = RoomStatus::AVAILABLE;
    return {{"success", "true"}};
}

// 5. check_in
ResultData check_in(const EventData& e, HotelStorage& s) {
    int resId = std::stoi(e.at("reservationId"));
    auto it = s.reservations.find(resId);
    if (it == s.reservations.end() || !it->second.active || it->second.checkedIn)
        return {{"success", "false"}};
    it->second.checkedIn = true;
    auto rit = s.rooms.find(it->second.roomId);
    if (rit != s.rooms.end()) rit->second.status = RoomStatus::OCCUPIED;
    return {{"success", "true"}};
}

// 6. check_out
ResultData check_out(const EventData& e, HotelStorage& s) {
    int resId = std::stoi(e.at("reservationId"));
    auto it = s.reservations.find(resId);
    if (it == s.reservations.end() || !it->second.active || !it->second.checkedIn)
        return {{"success", "false"}};
    it->second.checkedIn = false;
    it->second.active    = false;
    auto rit = s.rooms.find(it->second.roomId);
    if (rit != s.rooms.end()) rit->second.status = RoomStatus::CLEANING;
    return {{"success", "true"}};
}

// 7. process_payment
ResultData process_payment(const EventData& e, HotelStorage& s) {
    int id    = std::stoi(e.at("id"));
    int resId = std::stoi(e.at("reservationId"));
    double amount = std::stod(e.at("amount"));

    if (!s.reservations.count(resId)) return {{"success", "false"}, {"reason", "no_reservation"}};
    if (s.payments.count(id))         return {{"success", "false"}, {"reason", "duplicate"}};

    s.payments[id] = {id, resId, amount, true};
    return {{"success", "true"}};
}

// 8. assign_cleaning_task
ResultData assign_cleaning_task(const EventData& e, HotelStorage& s) {
    int id      = std::stoi(e.at("id"));
    int roomId  = std::stoi(e.at("roomId"));
    int staffId = std::stoi(e.at("staffId"));

    auto rit = s.rooms.find(roomId);
    if (rit == s.rooms.end() || rit->second.status != RoomStatus::CLEANING)
        return {{"success", "false"}};

    s.cleaningTasks[id] = {id, roomId, staffId, false};
    rit->second.status = RoomStatus::AVAILABLE;
    return {{"success", "true"}};
}

// 9. report_maintenance
ResultData report_maintenance(const EventData& e, HotelStorage& s) {
    int id     = std::stoi(e.at("id"));
    int roomId = std::stoi(e.at("roomId"));
    std::string description = e.at("description");
    std::string priority    = e.at("priority");

    auto rit = s.rooms.find(roomId);
    if (rit == s.rooms.end()) return {{"success", "false"}};

    s.maintenanceRequests[id] = {id, roomId, description, priority, false};
    if (priority == "HIGH" || priority == "EMERGENCY")
        rit->second.status = RoomStatus::MAINTENANCE;
    return {{"success", "true"}};
}

// 10. display_available_rooms
ResultData display_available_rooms(const EventData& /*e*/, HotelStorage& s) {
    int avail = 0;
    for (const auto& kv : s.rooms)
        if (kv.second.status == RoomStatus::AVAILABLE) avail++;

    ResultData result;
    result["available"] = std::to_string(avail);
    result["total"]      = std::to_string(s.rooms.size());
    std::cout << "[display_available_rooms] Available: " << result["available"]
              << " / " << result["total"] << "\n";
    return result;
}

// ─── Orchestrator implementation ───────────────────────────────────────────────
// Models an API-Gateway-style router: handlers are looked up by NAME (string
// key comparison through a std::map) and invoked indirectly through
// std::function, exactly like a cloud platform dispatches an incoming event
// to the correct registered handler.

void FaaSOrchestrator::registerFunction(const std::string& name, FaaSFn fn) {
    registry_[name] = std::move(fn);
}

ResultData FaaSOrchestrator::invoke(const std::string& name,
                                     const EventData& event, HotelStorage& storage) {
    auto it = registry_.find(name);
    if (it == registry_.end())
        return {{"success", "false"}, {"reason", "function_not_found"}};
    return it->second(event, storage);
}
