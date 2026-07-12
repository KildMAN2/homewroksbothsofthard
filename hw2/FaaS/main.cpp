/*
 * Hotel Management System — Function-as-a-Service (FaaS) Architecture
 *
 * Key FaaS Principles demonstrated:
 *  - Stateless execution: each function receives all needed data via EventData
 *  - Isolated functionality: no function calls another function directly
 *  - Minimal coupling: functions communicate only through an external store
 *  - Independent deployability: each function can be changed without affecting others
 *
 * In a real FaaS deployment (AWS Lambda, Azure Functions, GCP Cloud Functions)
 * the "sharedStore" would be a database or key-value service (DynamoDB, Redis, etc.)
 *
 * Implemented functions (10 total):
 *  1.  reserve_room
 *  2.  cancel_reservation
 *  3.  check_in_guest
 *  4.  check_out_guest
 *  5.  assign_housekeeping_to_floor
 *  6.  update_staff_shift
 *  7.  order_room_service
 *  8.  handle_maintenance_request
 *  9.  check_restaurant_capacity
 *  10. generate_daily_summary
 */

#include <iostream>
#include <string>
#include <map>
#include <functional>
#include <algorithm>
#include <ctime>

// ─── FaaS Type Aliases ────────────────────────────────────────────────────────

using EventData  = std::map<std::string, std::string>;
using ResultData = std::map<std::string, std::string>;
using FaaSFn     = std::function<ResultData(const EventData&)>;

// ─── Simulated External Store (replaces a cloud DB in real FaaS) ─────────────

static std::map<std::string, std::string> store;

static std::string storeGet(const std::string& key,
                            const std::string& def = "") {
    return store.count(key) ? store.at(key) : def;
}

static std::string nowStr() {
    time_t t = time(nullptr);
    char buf[20];
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M", localtime(&t));
    return std::string(buf);
}

// ─── FaaS Functions ───────────────────────────────────────────────────────────

// Function 1: reserve_room
// Finds the first available room of the requested type and reserves it.
ResultData reserveRoom(const EventData& ev) {
    ResultData res;
    std::string guestId   = ev.at("guest_id");
    std::string guestName = ev.at("guest_name");
    std::string roomType  = ev.at("room_type");   // SINGLE / DOUBLE / SUITE
    std::string checkIn   = ev.at("check_in");
    std::string checkOut  = ev.at("check_out");

    // Scan store for first available room of the matching type
    std::string foundRoom;
    for (auto& kv : store) {
        // Keys look like "room.101.type", "room.101.status"
        if (kv.first.size() > 5 &&
            kv.first.substr(0, 5) == "room." &&
            kv.first.find(".type") != std::string::npos &&
            kv.second == roomType) {
            // Extract room id
            std::string rid = kv.first.substr(5,
                              kv.first.find(".type") - 5);
            if (storeGet("room." + rid + ".status") == "AVAILABLE") {
                foundRoom = rid;
                break;
            }
        }
    }
    if (foundRoom.empty()) {
        res["status"]  = "ERROR";
        res["message"] = "No available " + roomType + " room.";
        std::cerr << "[reserve_room] " << res["message"] << "\n";
        return res;
    }
    store["room." + foundRoom + ".status"]    = "RESERVED";
    store["room." + foundRoom + ".guest"]     = guestName;
    store["room." + foundRoom + ".check_in"]  = checkIn;
    store["room." + foundRoom + ".check_out"] = checkOut;
    store["guest." + guestId + ".room"]       = foundRoom;

    res["status"]  = "OK";
    res["room_id"] = foundRoom;
    res["message"] = "Room " + foundRoom + " reserved for " + guestName
                     + " (" + checkIn + " -> " + checkOut + ")";
    std::cout << "[reserve_room]               " << res["message"] << "\n";
    return res;
}

// Function 2: cancel_reservation
ResultData cancelReservation(const EventData& ev) {
    ResultData res;
    std::string guestId   = ev.at("guest_id");
    std::string guestName = ev.at("guest_name");
    std::string roomId    = storeGet("guest." + guestId + ".room");

    if (roomId.empty() ||
        storeGet("room." + roomId + ".status") != "RESERVED") {
        res["status"]  = "ERROR";
        res["message"] = "No active reservation for guest " + guestId;
        std::cerr << "[cancel_reservation] " << res["message"] << "\n";
        return res;
    }
    store["room." + roomId + ".status"]    = "AVAILABLE";
    store["room." + roomId + ".guest"]     = "";
    store["room." + roomId + ".check_in"]  = "";
    store["room." + roomId + ".check_out"] = "";
    store["guest." + guestId + ".room"]    = "";

    res["status"]  = "OK";
    res["message"] = "Reservation cancelled for " + guestName
                     + " (room " + roomId + ")";
    std::cout << "[cancel_reservation]         " << res["message"] << "\n";
    return res;
}

// Function 3: check_in_guest
ResultData checkInGuest(const EventData& ev) {
    ResultData res;
    std::string guestId   = ev.at("guest_id");
    std::string guestName = ev.at("guest_name");
    std::string roomId    = storeGet("guest." + guestId + ".room");

    if (roomId.empty()) {
        res["status"]  = "ERROR";
        res["message"] = "Guest " + guestId + " has no reservation.";
        std::cerr << "[check_in_guest] " << res["message"] << "\n";
        return res;
    }
    store["room." + roomId + ".status"]        = "OCCUPIED";
    store["guest." + guestId + ".checked_in"]  = "1";

    res["status"]  = "OK";
    res["message"] = guestName + " checked into room " + roomId;
    std::cout << "[check_in_guest]             " << res["message"] << "\n";
    return res;
}

// Function 4: check_out_guest
ResultData checkOutGuest(const EventData& ev) {
    ResultData res;
    std::string guestId   = ev.at("guest_id");
    std::string guestName = ev.at("guest_name");
    std::string roomId    = storeGet("guest." + guestId + ".room");

    if (roomId.empty() ||
        storeGet("guest." + guestId + ".checked_in") != "1") {
        res["status"]  = "ERROR";
        res["message"] = "Guest " + guestId + " not checked in.";
        std::cerr << "[check_out_guest] " << res["message"] << "\n";
        return res;
    }
    store["room."  + roomId  + ".status"]       = "CLEANING";
    store["room."  + roomId  + ".guest"]        = "";
    store["guest." + guestId + ".checked_in"]   = "0";
    store["guest." + guestId + ".room"]         = "";

    res["status"]  = "OK";
    res["message"] = guestName + " checked out of room " + roomId
                     + " (queued for cleaning)";
    std::cout << "[check_out_guest]            " << res["message"] << "\n";
    return res;
}

// Function 5: assign_housekeeping_to_floor
ResultData assignHousekeepingToFloor(const EventData& ev) {
    ResultData res;
    std::string staffId   = ev.at("staff_id");
    std::string staffName = ev.at("staff_name");
    std::string floor     = ev.at("floor");

    if (storeGet("staff." + staffId + ".floor") == floor) {
        res["status"]  = "ERROR";
        res["message"] = staffName + " already on floor " + floor;
        return res;
    }
    store["staff." + staffId + ".floor"] = floor;

    // Mark all CLEANING rooms on that floor as AVAILABLE
    int cleaned = 0;
    for (auto& kv : store) {
        if (kv.first.size() > 5 &&
            kv.first.substr(0, 5) == "room." &&
            kv.first.find(".floor") != std::string::npos &&
            kv.second == floor) {
            std::string rid = kv.first.substr(5,
                              kv.first.find(".floor") - 5);
            if (storeGet("room." + rid + ".status") == "CLEANING") {
                store["room." + rid + ".status"] = "AVAILABLE";
                cleaned++;
            }
        }
    }
    res["status"]  = "OK";
    res["message"] = staffName + " assigned to floor " + floor
                     + " (" + std::to_string(cleaned) + " room(s) cleaned)";
    std::cout << "[assign_housekeeping_to_floor] " << res["message"] << "\n";
    return res;
}

// Function 6: update_staff_shift
ResultData updateStaffShift(const EventData& ev) {
    ResultData res;
    std::string staffId   = ev.at("staff_id");
    std::string staffName = ev.at("staff_name");
    std::string role      = ev.at("role");
    std::string start     = ev.at("shift_start");
    std::string end       = ev.at("shift_end");

    store["staff." + staffId + ".shift_start"] = start;
    store["staff." + staffId + ".shift_end"]   = end;
    store["staff." + staffId + ".on_duty"]     = "1";
    store["staff." + staffId + ".role"]        = role;

    res["status"]  = "OK";
    res["message"] = staffName + " (" + role + ") shift: " + start + " - " + end;
    std::cout << "[update_staff_shift]         " << res["message"] << "\n";
    return res;
}

// Function 7: order_room_service
ResultData orderRoomService(const EventData& ev) {
    ResultData res;
    std::string roomId    = ev.at("room_id");
    std::string guestName = ev.at("guest_name");
    std::string items     = ev.at("items");

    if (storeGet("room." + roomId + ".status") != "OCCUPIED") {
        res["status"]  = "ERROR";
        res["message"] = "Room " + roomId + " is not occupied.";
        std::cerr << "[order_room_service] " << res["message"] << "\n";
        return res;
    }
    int orderId = std::stoi(storeGet("order.count", "0")) + 1;
    store["order.count"]                            = std::to_string(orderId);
    store["order." + std::to_string(orderId) + ".room"]      = roomId;
    store["order." + std::to_string(orderId) + ".guest"]     = guestName;
    store["order." + std::to_string(orderId) + ".items"]     = items;
    store["order." + std::to_string(orderId) + ".time"]      = nowStr();
    store["order." + std::to_string(orderId) + ".delivered"] = "0";

    res["status"]    = "OK";
    res["order_id"]  = std::to_string(orderId);
    res["message"]   = "Order #" + std::to_string(orderId)
                       + " for room " + roomId + ": " + items;
    std::cout << "[order_room_service]         " << res["message"] << "\n";
    return res;
}

// Function 8: handle_maintenance_request
ResultData handleMaintenanceRequest(const EventData& ev) {
    ResultData res;
    std::string roomId = ev.at("room_id");
    std::string issue  = ev.at("issue");

    // Find on-duty maintenance staff
    std::string assignedStaff;
    for (auto& kv : store) {
        if (kv.first.find(".role") != std::string::npos &&
            kv.second == "Maintenance") {
            std::string sid = kv.first.substr(6,
                              kv.first.find(".role") - 6);
            if (storeGet("staff." + sid + ".on_duty") == "1") {
                assignedStaff = sid;
                break;
            }
        }
    }
    int reqId = std::stoi(storeGet("maint.count", "0")) + 1;
    store["maint.count"] = std::to_string(reqId);
    store["maint." + std::to_string(reqId) + ".room"]     = roomId;
    store["maint." + std::to_string(reqId) + ".issue"]    = issue;
    store["maint." + std::to_string(reqId) + ".time"]     = nowStr();
    store["maint." + std::to_string(reqId) + ".resolved"] = "0";
    store["maint." + std::to_string(reqId) + ".staff"]    = assignedStaff;
    store["room." + roomId + ".status"] = "MAINTENANCE";

    res["status"]    = "OK";
    res["request_id"]= std::to_string(reqId);
    res["message"]   = "Maintenance #" + std::to_string(reqId)
                       + " room " + roomId + ": " + issue
                       + (assignedStaff.empty() ? "" : " (staff #" + assignedStaff + ")");
    std::cout << "[handle_maintenance_request] " << res["message"] << "\n";
    return res;
}

// Function 9: check_restaurant_capacity
ResultData checkRestaurantCapacity(const EventData& ev) {
    ResultData res;
    std::string action    = ev.count("action") ? ev.at("action") : "query";
    int         capacity  = std::stoi(storeGet("restaurant.capacity", "60"));
    int         seated    = std::stoi(storeGet("restaurant.seated",   "0"));

    if (action == "seat") {
        int n = std::stoi(ev.at("guests"));
        if (seated + n > capacity) {
            res["status"]  = "ERROR";
            res["message"] = "Not enough seats (available: "
                             + std::to_string(capacity - seated) + ")";
            std::cerr << "[check_restaurant_capacity]  " << res["message"] << "\n";
            return res;
        }
        seated += n;
        store["restaurant.seated"] = std::to_string(seated);
        res["message"] = "Seated " + std::to_string(n) + " guests";
    } else if (action == "release") {
        int n = std::stoi(ev.at("guests"));
        seated = std::max(0, seated - n);
        store["restaurant.seated"] = std::to_string(seated);
        res["message"] = "Released " + std::to_string(n) + " seats";
    } else {
        res["message"] = "Query";
    }
    res["status"]    = "OK";
    res["seated"]    = std::to_string(seated);
    res["capacity"]  = std::to_string(capacity);
    res["available"] = std::to_string(capacity - seated);
    std::cout << "[check_restaurant_capacity]  " << res["message"]
              << " — " << seated << "/" << capacity << " seated\n";
    return res;
}

// Function 10: generate_daily_summary
ResultData generateDailySummary(const EventData& /*ev*/) {
    ResultData res;
    std::cout << "\n[generate_daily_summary] ====== DAILY HOTEL SUMMARY ======\n";

    // Count room statuses
    std::map<std::string, int> roomCounts;
    for (auto& kv : store) {
        if (kv.first.size() > 5 &&
            kv.first.substr(0, 5) == "room." &&
            kv.first.find(".status") != std::string::npos) {
            roomCounts[kv.second]++;
        }
    }
    std::cout << "[generate_daily_summary]   Rooms — "
              << "Occupied:"    << roomCounts["OCCUPIED"]    << "  "
              << "Reserved:"    << roomCounts["RESERVED"]    << "  "
              << "Available:"   << roomCounts["AVAILABLE"]   << "  "
              << "Cleaning:"    << roomCounts["CLEANING"]    << "  "
              << "Maintenance:" << roomCounts["MAINTENANCE"] << "\n";

    // Staff on duty
    int onDuty = 0;
    for (auto& kv : store) {
        if (kv.first.find(".on_duty") != std::string::npos && kv.second == "1")
            onDuty++;
    }
    std::cout << "[generate_daily_summary]   Staff on duty: " << onDuty << "\n";

    // Restaurant
    std::cout << "[generate_daily_summary]   Restaurant: "
              << storeGet("restaurant.seated", "0") << "/"
              << storeGet("restaurant.capacity", "60") << " seated\n";

    // Pending orders and maintenance
    int orders = std::stoi(storeGet("order.count", "0"));
    int maints = std::stoi(storeGet("maint.count",  "0"));
    std::cout << "[generate_daily_summary]   Room service orders: " << orders << "\n";
    std::cout << "[generate_daily_summary]   Maintenance requests: " << maints << "\n";
    std::cout << "[generate_daily_summary] ==================================\n\n";

    res["status"] = "OK";
    return res;
}

// ─── FaaS Orchestrator ────────────────────────────────────────────────────────
// Simulates the cloud provider's event router / API gateway.

class FaaSOrchestrator {
public:
    void registerFunction(const std::string& name, FaaSFn fn) {
        registry[name] = fn;
    }

    ResultData invoke(const std::string& name, const EventData& ev) {
        if (registry.count(name)) return registry[name](ev);
        std::cerr << "[orchestrator] Unknown function: " << name << "\n";
        return {{"status","ERROR"},{"message","Unknown function: " + name}};
    }

private:
    std::map<std::string, FaaSFn> registry;
};

// ─── Main ─────────────────────────────────────────────────────────────────────

int main() {
    std::cout << "=== Hotel Management System (FaaS Architecture) ===\n\n";

    // ── Bootstrap store (simulates provisioned infrastructure / DB seed) ──
    // Rooms
    auto seedRoom = [](const std::string& id, int floor,
                       const std::string& type, double price) {
        store["room." + id + ".floor"]  = std::to_string(floor);
        store["room." + id + ".type"]   = type;
        store["room." + id + ".status"] = "AVAILABLE";
        store["room." + id + ".price"]  = std::to_string(price);
    };
    seedRoom("101", 1, "SINGLE", 80);
    seedRoom("102", 1, "SINGLE", 80);
    seedRoom("201", 2, "DOUBLE", 140);
    seedRoom("202", 2, "DOUBLE", 140);
    seedRoom("301", 3, "SUITE",  300);
    seedRoom("302", 3, "SUITE",  300);

    store["restaurant.capacity"] = "60";
    store["restaurant.seated"]   = "0";

    // ── Register all functions ─────────────────────────────────────────────
    FaaSOrchestrator faas;
    faas.registerFunction("reserve_room",                 reserveRoom);
    faas.registerFunction("cancel_reservation",           cancelReservation);
    faas.registerFunction("check_in_guest",               checkInGuest);
    faas.registerFunction("check_out_guest",              checkOutGuest);
    faas.registerFunction("assign_housekeeping_to_floor", assignHousekeepingToFloor);
    faas.registerFunction("update_staff_shift",           updateStaffShift);
    faas.registerFunction("order_room_service",           orderRoomService);
    faas.registerFunction("handle_maintenance_request",   handleMaintenanceRequest);
    faas.registerFunction("check_restaurant_capacity",    checkRestaurantCapacity);
    faas.registerFunction("generate_daily_summary",       generateDailySummary);

    // ── Morning: staff shifts (independent triggers) ───────────────────────
    std::cout << "-- Morning Staff Shifts --\n";
    faas.invoke("update_staff_shift", {{"staff_id","1"},{"staff_name","Eve"},  {"role","Receptionist"},{"shift_start","07:00"},{"shift_end","15:00"}});
    faas.invoke("update_staff_shift", {{"staff_id","2"},{"staff_name","Frank"},{"role","Housekeeper"},  {"shift_start","08:00"},{"shift_end","16:00"}});
    faas.invoke("update_staff_shift", {{"staff_id","3"},{"staff_name","Grace"},{"role","Housekeeper"},  {"shift_start","08:00"},{"shift_end","16:00"}});
    faas.invoke("update_staff_shift", {{"staff_id","4"},{"staff_name","Henry"},{"role","Chef"},          {"shift_start","06:00"},{"shift_end","14:00"}});
    faas.invoke("update_staff_shift", {{"staff_id","5"},{"staff_name","Iris"}, {"role","Maintenance"},  {"shift_start","09:00"},{"shift_end","17:00"}});

    // ── Reservations ───────────────────────────────────────────────────────
    std::cout << "\n-- Reservations --\n";
    faas.invoke("reserve_room", {{"guest_id","1"},{"guest_name","Alice Johnson"},{"room_type","SUITE"},  {"check_in","2026-07-15"},{"check_out","2026-07-18"}});
    faas.invoke("reserve_room", {{"guest_id","2"},{"guest_name","Bob Martinez"}, {"room_type","DOUBLE"},{"check_in","2026-07-15"},{"check_out","2026-07-17"}});
    faas.invoke("reserve_room", {{"guest_id","3"},{"guest_name","Carol Smith"},  {"room_type","SINGLE"},{"check_in","2026-07-15"},{"check_out","2026-07-16"}});
    faas.invoke("reserve_room", {{"guest_id","4"},{"guest_name","David Lee"},    {"room_type","DOUBLE"},{"check_in","2026-07-15"},{"check_out","2026-07-19"}});

    // ── Cancel one ────────────────────────────────────────────────────────
    std::cout << "\n-- Cancellation --\n";
    faas.invoke("cancel_reservation", {{"guest_id","3"},{"guest_name","Carol Smith"}});

    // ── Check-ins ─────────────────────────────────────────────────────────
    std::cout << "\n-- Check-Ins --\n";
    faas.invoke("check_in_guest", {{"guest_id","1"},{"guest_name","Alice Johnson"}});
    faas.invoke("check_in_guest", {{"guest_id","2"},{"guest_name","Bob Martinez"}});
    faas.invoke("check_in_guest", {{"guest_id","4"},{"guest_name","David Lee"}});

    // ── Room service & maintenance ─────────────────────────────────────────
    std::cout << "\n-- Room Service & Maintenance --\n";
    faas.invoke("order_room_service",          {{"room_id","301"},{"guest_name","Alice Johnson"},{"items","Club sandwich, OJ, cheesecake"}});
    faas.invoke("order_room_service",          {{"room_id","201"},{"guest_name","Bob Martinez"}, {"items","Pasta, mineral water"}});
    faas.invoke("handle_maintenance_request",  {{"room_id","202"},{"issue","AC not cooling properly"}});

    // ── Restaurant ────────────────────────────────────────────────────────
    std::cout << "\n-- Restaurant --\n";
    faas.invoke("check_restaurant_capacity", {{"action","seat"},   {"guests","12"}});
    faas.invoke("check_restaurant_capacity", {{"action","seat"},   {"guests","8"}});
    faas.invoke("check_restaurant_capacity", {{"action","release"},{"guests","10"}});

    // ── Morning summary ───────────────────────────────────────────────────
    faas.invoke("generate_daily_summary", {});

    // ── Afternoon: check-out, housekeeping ────────────────────────────────
    std::cout << "-- Afternoon Check-Out & Housekeeping --\n";
    faas.invoke("check_out_guest",               {{"guest_id","2"},{"guest_name","Bob Martinez"}});
    faas.invoke("assign_housekeeping_to_floor",  {{"staff_id","3"},{"staff_name","Grace"},{"floor","2"}});
    faas.invoke("assign_housekeeping_to_floor",  {{"staff_id","2"},{"staff_name","Frank"},{"floor","1"}});

    // ── Evening summary ───────────────────────────────────────────────────
    faas.invoke("generate_daily_summary", {});

    return 0;
}
