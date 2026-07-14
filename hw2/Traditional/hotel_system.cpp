#include "hotel_system.h"
#include <iostream>

bool HotelSystem::addGuest(int id, const std::string& name, const std::string& phone) {
    if (guests_.count(id)) return false;
    guests_[id] = {id, name, phone};
    return true;
}

bool HotelSystem::addRoom(int id, RoomType type, double price, int floor) {
    if (rooms_.count(id)) return false;
    rooms_[id] = {id, type, RoomStatus::AVAILABLE, price, floor};
    return true;
}

bool HotelSystem::createReservation(int id, int guestId, int roomId,
                                     const std::string& checkIn,
                                     const std::string& checkOut) {
    if (!guests_.count(guestId)) return false;
    auto rit = rooms_.find(roomId);
    if (rit == rooms_.end()) return false;

    // Reject only if an existing ACTIVE reservation for this room overlaps the
    // requested date range. A room's current physical status (e.g. OCCUPIED
    // right now) does not by itself block booking a future, non-overlapping stay.
    for (const auto& kv : reservations_) {
        const Reservation& r = kv.second;
        if (r.roomId == roomId && r.active &&
            overlaps(checkIn, checkOut, r.checkIn, r.checkOut))
            return false;
    }

    reservations_[id] = {id, guestId, roomId, checkIn, checkOut, true, false};
    if (rit->second.status == RoomStatus::AVAILABLE)
        rit->second.status = RoomStatus::RESERVED;
    return true;
}

bool HotelSystem::cancelReservation(int reservationId) {
    auto it = reservations_.find(reservationId);
    if (it == reservations_.end() || !it->second.active || it->second.checkedIn)
        return false;
    it->second.active = false;
    auto rit = rooms_.find(it->second.roomId);
    if (rit != rooms_.end()) rit->second.status = RoomStatus::AVAILABLE;
    return true;
}

bool HotelSystem::checkIn(int reservationId) {
    auto it = reservations_.find(reservationId);
    if (it == reservations_.end() || !it->second.active || it->second.checkedIn)
        return false;
    it->second.checkedIn = true;
    auto rit = rooms_.find(it->second.roomId);
    if (rit != rooms_.end()) rit->second.status = RoomStatus::OCCUPIED;
    return true;
}

bool HotelSystem::checkOut(int reservationId) {
    auto it = reservations_.find(reservationId);
    if (it == reservations_.end() || !it->second.active || !it->second.checkedIn)
        return false;
    it->second.checkedIn = false;
    it->second.active    = false;
    auto rit = rooms_.find(it->second.roomId);
    if (rit != rooms_.end()) rit->second.status = RoomStatus::CLEANING;
    return true;
}

bool HotelSystem::processPayment(int paymentId, int reservationId, double amount) {
    if (!reservations_.count(reservationId)) return false;
    if (payments_.count(paymentId))          return false;
    payments_[paymentId] = {paymentId, reservationId, amount, true};
    return true;
}

bool HotelSystem::assignCleaningTask(int taskId, int roomId, int staffId) {
    auto rit = rooms_.find(roomId);
    if (rit == rooms_.end() || rit->second.status != RoomStatus::CLEANING) return false;
    cleaningTasks_[taskId] = {taskId, roomId, staffId, false};
    // Task is only ASSIGNED here -- the room stays CLEANING until the task is
    // completed via completeCleaningTask(). Assigning a task must not itself
    // mean the room is already clean.
    return true;
}

bool HotelSystem::completeCleaningTask(int taskId) {
    auto it = cleaningTasks_.find(taskId);
    if (it == cleaningTasks_.end() || it->second.completed) return false;
    it->second.completed = true;
    auto rit = rooms_.find(it->second.roomId);
    if (rit != rooms_.end()) rit->second.status = RoomStatus::AVAILABLE;
    return true;
}

bool HotelSystem::reportMaintenance(int requestId, int roomId,
                                     const std::string& description,
                                     const std::string& priority) {
    if (!rooms_.count(roomId)) return false;
    maintenanceRequests_[requestId] = {requestId, roomId, description, priority, false};
    if (priority == "HIGH" || priority == "EMERGENCY")
        rooms_[roomId].status = RoomStatus::MAINTENANCE;
    return true;
}

void HotelSystem::displayAvailableRooms() const {
    int avail = 0;
    for (const auto& kv : rooms_)
        if (kv.second.status == RoomStatus::AVAILABLE) avail++;
    std::cout << "[displayAvailableRooms] Available: " << avail
              << " / " << rooms_.size() << "\n";
}

// ── Part 3 extension ──────────────────────────────────────────────────────────
// Adding this feature required modifying BOTH hotel_system.h AND hotel_system.cpp.
// The method directly accesses private members (rooms_, reservations_, guests_).
// This is the coupling cost of the Traditional architecture.

bool HotelSystem::emergencyMaintenance(int requestId, int roomId,
                                        const std::string& issue) {
    auto rit = rooms_.find(roomId);
    if (rit == rooms_.end()) return false;

    // Step 1: mark room under maintenance
    maintenanceRequests_[requestId] = {requestId, roomId, issue, "EMERGENCY", false};
    rit->second.status = RoomStatus::MAINTENANCE;

    // Step 2: find active reservation for this room
    int affectedGuestId = -1, affectedResId = -1;
    for (auto& kv : reservations_) {
        if (kv.second.roomId == roomId && kv.second.active) {
            affectedGuestId = kv.second.guestId;
            affectedResId   = kv.second.id;
            break;
        }
    }
    if (affectedResId == -1) {
        std::cout << "[emergencyMaintenance] Room " << roomId
                  << " -> MAINTENANCE. No active reservations affected.\n";
        return true;
    }

    // Step 3: find replacement room of same type
    RoomType needed = rit->second.type;
    int replId = -1;
    for (auto& kv : rooms_) {
        if (kv.first != roomId &&
            kv.second.type == needed &&
            kv.second.status == RoomStatus::AVAILABLE) {
            replId = kv.first;
            break;
        }
    }
    if (replId == -1) {
        std::cout << "[emergencyMaintenance] No replacement room found. Manual intervention needed.\n";
        return true;
    }

    // Step 4: reassign reservation
    reservations_[affectedResId].roomId = replId;
    rooms_[replId].status = RoomStatus::RESERVED;

    // Step 5: notify guest
    std::string guestName = guests_.count(affectedGuestId) ?
                            guests_.at(affectedGuestId).name : "Unknown";
    std::cout << "[emergencyMaintenance] Room " << roomId << " EMERGENCY: " << issue << "\n"
              << "  Res #" << affectedResId << " reassigned: Room " << roomId
              << " -> Room " << replId << "\n"
              << "  Guest " << guestName << " notified: new room is " << replId << "\n";
    return true;
}
