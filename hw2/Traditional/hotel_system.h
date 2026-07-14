#pragma once
#include "models.h"
#include <map>
#include <vector>
#include <string>

class HotelSystem {
public:
    // ── Core 11 operations ───────────────────────────────────────────────────
    bool addGuest(int id, const std::string& name, const std::string& phone);
    bool addRoom(int id, RoomType type, double price, int floor);
    // Reserves the room for [checkIn, checkOut) if no OTHER active reservation
    // for that room overlaps the requested date range (see models.h::overlaps).
    bool createReservation(int id, int guestId, int roomId,
                           const std::string& checkIn, const std::string& checkOut);
    bool cancelReservation(int reservationId);
    bool checkIn(int reservationId);
    bool checkOut(int reservationId);
    bool processPayment(int paymentId, int reservationId, double amount);
    // Assigns a cleaning task to a room currently in CLEANING status. The task
    // is only ASSIGNED here; the room stays CLEANING until completeCleaningTask()
    // is called. (Splitting this into two operations was a correctness fix --
    // assigning a task must not itself mean the cleaning is already done.)
    bool assignCleaningTask(int taskId, int roomId, int staffId);
    // Marks a previously assigned cleaning task as finished and frees the room.
    bool completeCleaningTask(int taskId);
    bool reportMaintenance(int requestId, int roomId,
                           const std::string& description,
                           const std::string& priority);
    void displayAvailableRooms() const;

    // ── Part 3: Emergency auto-reassignment ──────────────────────────────────
    // NOTE: Adding this required modifying hotel_system.h and hotel_system.cpp.
    // All cross-cutting logic lives inside the class — demonstrating coupling.
    bool emergencyMaintenance(int requestId, int roomId, const std::string& issue);

private:
    std::map<int, Guest>              guests_;
    std::map<int, Room>               rooms_;
    std::map<int, Reservation>        reservations_;
    std::map<int, Payment>            payments_;
    std::map<int, CleaningTask>       cleaningTasks_;
    std::map<int, MaintenanceRequest> maintenanceRequests_;
    // roomId -> IDs of that room's currently-active reservations. Keeps the
    // date-overlap check in createReservation() bounded by the (small) number
    // of active bookings for ONE room instead of the total reservation count
    // ever created (which would otherwise be an O(n) scan across all rooms
    // and grow without bound over the system's lifetime).
    std::map<int, std::vector<int>>   roomReservationIndex_;
};
