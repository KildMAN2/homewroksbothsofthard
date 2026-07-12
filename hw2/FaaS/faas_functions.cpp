#include "faas_functions.h"
#include <iostream>

// ─────────────────────────────────────────────────────────────────────────────
// FaaS Hotel Management System — all 10 independent functions
//
// Each function follows the same contract:
//   1. Receive a typed event
//   2. Load required data from external storage
//   3. Validate the request
//   4. Perform exactly ONE task
//   5. Store the result
//   6. Return and exit
//
// Functions are stateless: they own NO data. Storage is always external.
// ─────────────────────────────────────────────────────────────────────────────

// 1. add_guest ─────────────────────────────────────────────────────────────────
bool add_guest(const AddGuestEvent& e, HotelStorage& s) {
    for (const Guest& g : s.guests)
        if (g.id == e.id) return false;        // reject duplicate
    s.guests.push_back({e.id, e.name, e.phone});
    return true;
}

// 2. add_room ──────────────────────────────────────────────────────────────────
bool add_room(const AddRoomEvent& e, HotelStorage& s) {
    for (const Room& r : s.rooms)
        if (r.id == e.id) return false;
    s.rooms.push_back({e.id, e.type, RoomStatus::AVAILABLE, e.pricePerNight, e.floor});
    return true;
}

// 3. create_reservation ────────────────────────────────────────────────────────
bool create_reservation(const CreateReservationEvent& e, HotelStorage& s) {
    bool guestFound = false;
    for (const Guest& g : s.guests)
        if (g.id == e.guestId) { guestFound = true; break; }
    if (!guestFound) return false;

    Room* room = nullptr;
    for (Room& r : s.rooms)
        if (r.id == e.roomId) { room = &r; break; }
    if (!room || room->status != RoomStatus::AVAILABLE) return false;

    s.reservations.push_back({e.id, e.guestId, e.roomId,
                               e.checkIn, e.checkOut, true, false});
    room->status = RoomStatus::RESERVED;
    return true;
}

// 4. cancel_reservation ────────────────────────────────────────────────────────
bool cancel_reservation(const CancelReservationEvent& e, HotelStorage& s) {
    for (Reservation& res : s.reservations) {
        if (res.id == e.reservationId && res.active && !res.checkedIn) {
            res.active = false;
            for (Room& r : s.rooms)
                if (r.id == res.roomId) { r.status = RoomStatus::AVAILABLE; break; }
            return true;
        }
    }
    return false;
}

// 5. check_in ──────────────────────────────────────────────────────────────────
bool check_in(const CheckInEvent& e, HotelStorage& s) {
    for (Reservation& res : s.reservations) {
        if (res.id == e.reservationId && res.active && !res.checkedIn) {
            res.checkedIn = true;
            for (Room& r : s.rooms)
                if (r.id == res.roomId) { r.status = RoomStatus::OCCUPIED; break; }
            return true;
        }
    }
    return false;
}

// 6. check_out ─────────────────────────────────────────────────────────────────
bool check_out(const CheckOutEvent& e, HotelStorage& s) {
    for (Reservation& res : s.reservations) {
        if (res.id == e.reservationId && res.active && res.checkedIn) {
            res.checkedIn = false;
            res.active    = false;
            for (Room& r : s.rooms)
                if (r.id == res.roomId) { r.status = RoomStatus::CLEANING; break; }
            return true;
        }
    }
    return false;
}

// 7. process_payment ───────────────────────────────────────────────────────────
bool process_payment(const ProcessPaymentEvent& e, HotelStorage& s) {
    bool found = false;
    for (const Reservation& res : s.reservations)
        if (res.id == e.reservationId) { found = true; break; }
    if (!found) return false;

    for (const Payment& p : s.payments)
        if (p.id == e.id) return false;     // prevent duplicate

    s.payments.push_back({e.id, e.reservationId, e.amount, true});
    return true;
}

// 8. assign_cleaning_task ──────────────────────────────────────────────────────
bool assign_cleaning_task(const AssignCleaningTaskEvent& e, HotelStorage& s) {
    Room* room = nullptr;
    for (Room& r : s.rooms)
        if (r.id == e.roomId) { room = &r; break; }
    if (!room || room->status != RoomStatus::CLEANING) return false;

    s.cleaningTasks.push_back({e.id, e.roomId, e.staffId, false});
    room->status = RoomStatus::AVAILABLE;
    return true;
}

// 9. report_maintenance ────────────────────────────────────────────────────────
bool report_maintenance(const ReportMaintenanceEvent& e, HotelStorage& s) {
    Room* room = nullptr;
    for (Room& r : s.rooms)
        if (r.id == e.roomId) { room = &r; break; }
    if (!room) return false;

    s.maintenanceRequests.push_back({e.id, e.roomId, e.description, e.priority, false});
    if (e.priority == "HIGH" || e.priority == "EMERGENCY")
        room->status = RoomStatus::MAINTENANCE;
    return true;
}

// 10. display_available_rooms ──────────────────────────────────────────────────
void display_available_rooms(const HotelStorage& s) {
    int avail = 0;
    for (const Room& r : s.rooms)
        if (r.status == RoomStatus::AVAILABLE) avail++;
    std::cout << "[display_available_rooms] Available: " << avail
              << " / " << s.rooms.size() << "\n";
}
