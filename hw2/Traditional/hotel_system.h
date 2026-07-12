#pragma once
#include "models.h"
#include <map>
#include <string>

class HotelSystem {
public:
    // ── Core 10 operations ───────────────────────────────────────────────────
    bool addGuest(int id, const std::string& name, const std::string& phone);
    bool addRoom(int id, RoomType type, double price, int floor);
    bool createReservation(int id, int guestId, int roomId,
                           const std::string& checkIn, const std::string& checkOut);
    bool cancelReservation(int reservationId);
    bool checkIn(int reservationId);
    bool checkOut(int reservationId);
    bool processPayment(int paymentId, int reservationId, double amount);
    bool assignCleaningTask(int taskId, int roomId, int staffId);
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
};
