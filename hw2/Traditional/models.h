#pragma once
#include <string>

enum class RoomType   { SINGLE, DOUBLE, SUITE };
enum class RoomStatus { AVAILABLE, OCCUPIED, RESERVED, MAINTENANCE, CLEANING };

struct Guest {
    int         id;
    std::string name;
    std::string phone;
};

struct Room {
    int        id;
    RoomType   type;
    RoomStatus status;
    double     pricePerNight;
    int        floor;
};

struct Reservation {
    int         id;
    int         guestId;
    int         roomId;
    std::string checkIn;
    std::string checkOut;
    bool        active;    // false if cancelled or checked-out
    bool        checkedIn;
};

struct Payment {
    int    id;
    int    reservationId;
    double amount;
    bool   processed;
};

struct CleaningTask {
    int  id;
    int  roomId;
    int  assignedStaffId;
    bool completed;
};

struct MaintenanceRequest {
    int         id;
    int         roomId;
    std::string description;
    std::string priority;   // LOW / MEDIUM / HIGH / EMERGENCY
    bool        resolved;
};
