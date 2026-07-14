#pragma once
#include "models.h"
#include <map>
#include <vector>

// External storage simulates a cloud database shared by all FaaS functions.
// Functions receive a reference -- they do NOT own this data.
// Records are keyed by ID (an indexed store, like a real cloud key-value DB).
struct HotelStorage {
    std::map<int, Guest>              guests;
    std::map<int, Room>               rooms;
    std::map<int, Reservation>        reservations;
    std::map<int, Payment>            payments;
    std::map<int, CleaningTask>       cleaningTasks;
    std::map<int, MaintenanceRequest> maintenanceRequests;
    // roomId -> IDs of that room's currently-active reservations. Keeps the
    // date-overlap check in create_reservation() bounded by the (small) number
    // of active bookings for ONE room instead of scanning every reservation
    // ever created system-wide.
    std::map<int, std::vector<int>>   roomReservationIndex;
};
