#include "faas_functions.h"
#include <iostream>

// ─────────────────────────────────────────────────────────────────────────────
// FaaS Hotel Management System -- all 10 independent functions
//
// Each function follows the same contract:
//   1. Receive a typed event
//   2. Load required data from external storage
//   3. Validate the request
//   4. Perform exactly ONE task
//   5. Store the result
//   6. Return and exit
//
// Functions are stateless: they own NO data. Storage is always external and
// indexed by ID (std::map), mirroring an indexed cloud key-value database.
// ─────────────────────────────────────────────────────────────────────────────

// 1. add_guest
bool add_guest(const AddGuestEvent& e, HotelStorage& s) {
    if (s.guests.count(e.id)) return false;        // reject duplicate
    s.guests[e.id] = {e.id, e.name, e.phone};
    return true;
}

// 2. add_room
bool add_room(const AddRoomEvent& e, HotelStorage& s) {
    if (s.rooms.count(e.id)) return false;
    s.rooms[e.id] = {e.id, e.type, RoomStatus::AVAILABLE, e.pricePerNight, e.floor};
    return true;
}

// 3. create_reservation
bool create_reservation(const CreateReservationEvent& e, HotelStorage& s) {
    if (!s.guests.count(e.guestId)) return false;
    auto rit = s.rooms.find(e.roomId);
    if (rit == s.rooms.end() || rit->second.status != RoomStatus::AVAILABLE) return false;
    s.reservations[e.id] = {e.id, e.guestId, e.roomId, e.checkIn, e.checkOut, true, false};
    rit->second.status = RoomStatus::RESERVED;
    return true;
}

// 4. cancel_reservation
bool cancel_reservation(const CancelReservationEvent& e, HotelStorage& s) {
    auto it = s.reservations.find(e.reservationId);
    if (it == s.reservations.end() || !it->second.active || it->second.checkedIn) return false;
    it->second.active = false;
    auto rit = s.rooms.find(it->second.roomId);
    if (rit != s.rooms.end()) rit->second.status = RoomStatus::AVAILABLE;
    return true;
}

// 5. check_in
bool check_in(const CheckInEvent& e, HotelStorage& s) {
    auto it = s.reservations.find(e.reservationId);
    if (it == s.reservations.end() || !it->second.active || it->second.checkedIn) return false;
    it->second.checkedIn = true;
    auto rit = s.rooms.find(it->second.roomId);
    if (rit != s.rooms.end()) rit->second.status = RoomStatus::OCCUPIED;
    return true;
}

// 6. check_out
bool check_out(const CheckOutEvent& e, HotelStorage& s) {
    auto it = s.reservations.find(e.reservationId);
    if (it == s.reservations.end() || !it->second.active || !it->second.checkedIn) return false;
    it->second.checkedIn = false;
    it->second.active    = false;
    auto rit = s.rooms.find(it->second.roomId);
    if (rit != s.rooms.end()) rit->second.status = RoomStatus::CLEANING;
    return true;
}

// 7. process_payment
bool process_payment(const ProcessPaymentEvent& e, HotelStorage& s) {
    if (!s.reservations.count(e.reservationId)) return false;
    if (s.payments.count(e.id))                 return false;   // prevent duplicate
    s.payments[e.id] = {e.id, e.reservationId, e.amount, true};
    return true;
}

// 8. assign_cleaning_task
bool assign_cleaning_task(const AssignCleaningTaskEvent& e, HotelStorage& s) {
    auto rit = s.rooms.find(e.roomId);
    if (rit == s.rooms.end() || rit->second.status != RoomStatus::CLEANING) return false;
    s.cleaningTasks[e.id] = {e.id, e.roomId, e.staffId, false};
    rit->second.status = RoomStatus::AVAILABLE;
    return true;
}

// 9. report_maintenance
bool report_maintenance(const ReportMaintenanceEvent& e, HotelStorage& s) {
    auto rit = s.rooms.find(e.roomId);
    if (rit == s.rooms.end()) return false;
    s.maintenanceRequests[e.id] = {e.id, e.roomId, e.description, e.priority, false};
    if (e.priority == "HIGH" || e.priority == "EMERGENCY")
        rit->second.status = RoomStatus::MAINTENANCE;
    return true;
}

// 10. display_available_rooms
void display_available_rooms(const HotelStorage& s) {
    int avail = 0;
    for (const auto& kv : s.rooms)
        if (kv.second.status == RoomStatus::AVAILABLE) avail++;
    std::cout << "[display_available_rooms] Available: " << avail
              << " / " << s.rooms.size() << "\n";
}
