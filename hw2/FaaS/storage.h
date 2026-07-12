#pragma once
#include "models.h"
#include <vector>

// External storage simulates a cloud database shared by all FaaS functions.
// Functions receive a reference — they do NOT own this data.
struct HotelStorage {
    std::vector<Guest>              guests;
    std::vector<Room>               rooms;
    std::vector<Reservation>        reservations;
    std::vector<Payment>            payments;
    std::vector<CleaningTask>       cleaningTasks;
    std::vector<MaintenanceRequest> maintenanceRequests;
};
