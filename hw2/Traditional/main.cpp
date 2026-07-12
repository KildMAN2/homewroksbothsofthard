/*
 * Hotel Management System — Traditional Monolithic Architecture
 *
 * All system state is owned by a single HotelSystem class.
 * Operations are methods that directly access and mutate shared state.
 * This mirrors how real-world traditional server applications are built.
 *
 * Implemented operations (10 total):
 *  1.  reserveRoom
 *  2.  cancelReservation
 *  3.  checkInGuest
 *  4.  checkOutGuest
 *  5.  assignHousekeepingToFloor
 *  6.  updateStaffShift
 *  7.  orderRoomService
 *  8.  handleMaintenanceRequest
 *  9.  checkRestaurantCapacity
 *  10. generateDailyReport
 */

#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <algorithm>
#include <ctime>

// ─── Data Structures ──────────────────────────────────────────────────────────

enum class RoomType  { SINGLE, DOUBLE, SUITE };
enum class RoomStatus{ AVAILABLE, RESERVED, OCCUPIED, CLEANING, MAINTENANCE };

struct Room {
    int        id;
    int        floor;
    RoomType   type;
    RoomStatus status;
    double     pricePerNight;
    std::string guestName;
    std::string checkInDate;
    std::string checkOutDate;
};

struct Guest {
    int         id;
    std::string name;
    std::string contact;
    int         assignedRoom;   // -1 if not assigned
    bool        checkedIn;
};

struct Staff {
    int         id;
    std::string name;
    std::string role;           // Housekeeper, Receptionist, Chef, Maintenance
    std::string shiftStart;
    std::string shiftEnd;
    bool        onDuty;
    int         assignedFloor;  // -1 if unassigned
};

struct RoomServiceOrder {
    int         orderId;
    int         roomId;
    std::string guestName;
    std::string items;
    std::string orderTime;
    bool        delivered;
};

struct MaintenanceRequest {
    int         requestId;
    int         roomId;
    std::string issue;
    std::string reportedTime;
    bool        resolved;
    int         assignedStaffId;
};

struct Restaurant {
    int capacity;
    int seated;
};

// ─── Hotel System ─────────────────────────────────────────────────────────────

class HotelSystem {
public:
    HotelSystem() { initializeHotel(); }

    // ── Operation 1: Reserve room ──────────────────────────────────────────
    bool reserveRoom(int guestId, RoomType type,
                     const std::string& checkIn, const std::string& checkOut) {
        auto git = guests.find(guestId);
        if (git == guests.end()) {
            std::cerr << "[RESERVE] Guest " << guestId << " not found.\n";
            return false;
        }
        for (auto& kv : rooms) {
            Room& r = kv.second;
            if (r.type == type && r.status == RoomStatus::AVAILABLE) {
                r.status       = RoomStatus::RESERVED;
                r.guestName    = git->second.name;
                r.checkInDate  = checkIn;
                r.checkOutDate = checkOut;
                git->second.assignedRoom = r.id;
                std::cout << "[RESERVE]   Room " << r.id << " reserved for "
                          << git->second.name << " (" << checkIn
                          << " → " << checkOut << ")\n";
                return true;
            }
        }
        std::cerr << "[RESERVE] No available room of requested type.\n";
        return false;
    }

    // ── Operation 2: Cancel reservation ───────────────────────────────────
    bool cancelReservation(int guestId) {
        auto git = guests.find(guestId);
        if (git == guests.end() || git->second.assignedRoom == -1) {
            std::cerr << "[CANCEL] No active reservation for guest " << guestId << "\n";
            return false;
        }
        int roomId = git->second.assignedRoom;
        auto rit   = rooms.find(roomId);
        if (rit != rooms.end() && rit->second.status == RoomStatus::RESERVED) {
            rit->second.status = RoomStatus::AVAILABLE;
            rit->second.guestName.clear();
            rit->second.checkInDate.clear();
            rit->second.checkOutDate.clear();
        }
        git->second.assignedRoom = -1;
        std::cout << "[CANCEL]    Reservation cancelled for "
                  << git->second.name << " (room " << roomId << ")\n";
        return true;
    }

    // ── Operation 3: Check in guest ───────────────────────────────────────
    bool checkInGuest(int guestId) {
        auto git = guests.find(guestId);
        if (git == guests.end()) {
            std::cerr << "[CHECK-IN] Guest " << guestId << " not found.\n";
            return false;
        }
        int roomId = git->second.assignedRoom;
        if (roomId == -1) {
            std::cerr << "[CHECK-IN] Guest has no reservation.\n";
            return false;
        }
        auto rit = rooms.find(roomId);
        if (rit == rooms.end()) return false;
        rit->second.status    = RoomStatus::OCCUPIED;
        git->second.checkedIn = true;
        std::cout << "[CHECK-IN]  " << git->second.name
                  << " checked into room " << roomId << "\n";
        return true;
    }

    // ── Operation 4: Check out guest ──────────────────────────────────────
    bool checkOutGuest(int guestId) {
        auto git = guests.find(guestId);
        if (git == guests.end() || !git->second.checkedIn) {
            std::cerr << "[CHECK-OUT] Guest not found or not checked in.\n";
            return false;
        }
        int roomId = git->second.assignedRoom;
        auto rit   = rooms.find(roomId);
        if (rit != rooms.end()) {
            rit->second.status = RoomStatus::CLEANING;
            rit->second.guestName.clear();
        }
        git->second.checkedIn    = false;
        git->second.assignedRoom = -1;
        std::cout << "[CHECK-OUT] " << git->second.name
                  << " checked out of room " << roomId
                  << " (room queued for cleaning)\n";
        return true;
    }

    // ── Operation 5: Assign housekeeping to floor ──────────────────────────
    bool assignHousekeepingToFloor(int staffId, int floor) {
        auto sit = staff.find(staffId);
        if (sit == staff.end() || sit->second.role != "Housekeeper") {
            std::cerr << "[HOUSEKEEPING] Staff " << staffId
                      << " not found or not a housekeeper.\n";
            return false;
        }
        if (sit->second.assignedFloor != -1) {
            std::cerr << "[HOUSEKEEPING] " << sit->second.name
                      << " already on floor " << sit->second.assignedFloor << "\n";
            return false;
        }
        sit->second.assignedFloor = floor;
        // Mark cleaning rooms on that floor as available
        for (auto& kv : rooms) {
            if (kv.second.floor == floor &&
                kv.second.status == RoomStatus::CLEANING) {
                kv.second.status = RoomStatus::AVAILABLE;
            }
        }
        std::cout << "[HOUSEKEEPING] " << sit->second.name
                  << " assigned to floor " << floor << "\n";
        return true;
    }

    // ── Operation 6: Update staff shift ───────────────────────────────────
    bool updateStaffShift(int staffId,
                          const std::string& start, const std::string& end) {
        auto sit = staff.find(staffId);
        if (sit == staff.end()) {
            std::cerr << "[SHIFT] Staff " << staffId << " not found.\n";
            return false;
        }
        sit->second.shiftStart = start;
        sit->second.shiftEnd   = end;
        sit->second.onDuty     = true;
        std::cout << "[SHIFT]     " << sit->second.name
                  << " (" << sit->second.role << ") shift: "
                  << start << " – " << end << "\n";
        return true;
    }

    // ── Operation 7: Order room service ───────────────────────────────────
    bool orderRoomService(int roomId, const std::string& items) {
        auto rit = rooms.find(roomId);
        if (rit == rooms.end() || rit->second.status != RoomStatus::OCCUPIED) {
            std::cerr << "[ROOM-SVC] Room " << roomId
                      << " not found or not occupied.\n";
            return false;
        }
        int orderId = (int)serviceOrders.size() + 1;
        RoomServiceOrder order;
        order.orderId   = orderId;
        order.roomId    = roomId;
        order.guestName = rit->second.guestName;
        order.items     = items;
        order.orderTime = timestamp();
        order.delivered = false;
        serviceOrders.push_back(order);
        std::cout << "[ROOM-SVC]  Order #" << orderId << " for room " << roomId
                  << " (" << rit->second.guestName << "): " << items << "\n";
        return true;
    }

    // ── Operation 8: Handle maintenance request ────────────────────────────
    bool handleMaintenanceRequest(int roomId, const std::string& issue) {
        auto rit = rooms.find(roomId);
        if (rit == rooms.end()) {
            std::cerr << "[MAINT] Room " << roomId << " not found.\n";
            return false;
        }
        // Find an available maintenance staff
        int assignedId = -1;
        for (auto& kv : staff) {
            if (kv.second.role == "Maintenance" && kv.second.onDuty) {
                assignedId = kv.second.id;
                break;
            }
        }
        int reqId = (int)maintenanceRequests.size() + 1;
        maintenanceRequests.push_back(
            {reqId, roomId, issue, timestamp(), false, assignedId});
        rit->second.status = RoomStatus::MAINTENANCE;
        std::cout << "[MAINT]     Request #" << reqId << " — room " << roomId
                  << ": " << issue;
        if (assignedId != -1)
            std::cout << " (assigned to " << staff[assignedId].name << ")";
        std::cout << "\n";
        return true;
    }

    // ── Operation 9: Check restaurant capacity ─────────────────────────────
    bool seatGuestsInRestaurant(int numGuests) {
        int available = restaurant.capacity - restaurant.seated;
        if (numGuests > available) {
            std::cerr << "[RESTAURANT] Not enough seats (available: "
                      << available << ")\n";
            return false;
        }
        restaurant.seated += numGuests;
        std::cout << "[RESTAURANT] Seated " << numGuests << " guests. "
                  << "Occupancy: " << restaurant.seated << "/"
                  << restaurant.capacity << "\n";
        return true;
    }

    void releaseRestaurantSeats(int numGuests) {
        restaurant.seated = std::max(0, restaurant.seated - numGuests);
        std::cout << "[RESTAURANT] Released " << numGuests << " seats. "
                  << "Occupancy: " << restaurant.seated << "/"
                  << restaurant.capacity << "\n";
    }

    // ── Operation 10: Generate daily report ───────────────────────────────
    void generateDailyReport() const {
        std::cout << "\n========== DAILY HOTEL REPORT ==========\n";
        int avail = 0, occupied = 0, cleaning = 0, maint = 0, reserved = 0;
        for (const auto& kv : rooms) {
            switch (kv.second.status) {
                case RoomStatus::AVAILABLE:    avail++;    break;
                case RoomStatus::OCCUPIED:     occupied++; break;
                case RoomStatus::CLEANING:     cleaning++; break;
                case RoomStatus::MAINTENANCE:  maint++;    break;
                case RoomStatus::RESERVED:     reserved++; break;
            }
        }
        std::cout << "Rooms      — Total: " << rooms.size()
                  << "  Occupied: "  << occupied
                  << "  Reserved: "  << reserved
                  << "  Available: " << avail
                  << "  Cleaning: "  << cleaning
                  << "  Maint: "     << maint << "\n";
        int onDuty = 0;
        for (const auto& kv : staff) if (kv.second.onDuty) onDuty++;
        std::cout << "Staff      — On duty: " << onDuty
                  << "/" << staff.size() << "\n";
        std::cout << "Restaurant — " << restaurant.seated
                  << "/" << restaurant.capacity << " seated\n";
        std::cout << "Room Svc   — Orders pending: ";
        int pending = 0;
        for (const auto& o : serviceOrders) if (!o.delivered) pending++;
        std::cout << pending << "\n";
        std::cout << "Maintenance— Open requests: ";
        int open = 0;
        for (const auto& r : maintenanceRequests) if (!r.resolved) open++;
        std::cout << open << "\n";
        std::cout << "=========================================\n\n";
    }

private:
    std::map<int, Room>              rooms;
    std::map<int, Guest>             guests;
    std::map<int, Staff>             staff;
    Restaurant                       restaurant;
    std::vector<RoomServiceOrder>    serviceOrders;
    std::vector<MaintenanceRequest>  maintenanceRequests;

    static std::string timestamp() {
        time_t now = time(nullptr);
        char buf[20];
        strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M", localtime(&now));
        return std::string(buf);
    }

    void initializeHotel() {
        // Rooms: floor, type, price
        rooms[101] = {101, 1, RoomType::SINGLE, RoomStatus::AVAILABLE, 80.0,  "", "", ""};
        rooms[102] = {102, 1, RoomType::SINGLE, RoomStatus::AVAILABLE, 80.0,  "", "", ""};
        rooms[201] = {201, 2, RoomType::DOUBLE, RoomStatus::AVAILABLE, 140.0, "", "", ""};
        rooms[202] = {202, 2, RoomType::DOUBLE, RoomStatus::AVAILABLE, 140.0, "", "", ""};
        rooms[301] = {301, 3, RoomType::SUITE,  RoomStatus::AVAILABLE, 300.0, "", "", ""};
        rooms[302] = {302, 3, RoomType::SUITE,  RoomStatus::AVAILABLE, 300.0, "", "", ""};

        // Guests
        guests[1] = {1, "Alice Johnson", "alice@email.com", -1, false};
        guests[2] = {2, "Bob Martinez",  "bob@email.com",   -1, false};
        guests[3] = {3, "Carol Smith",   "carol@email.com", -1, false};
        guests[4] = {4, "David Lee",     "david@email.com", -1, false};

        // Staff
        staff[1] = {1, "Eve",    "Receptionist", "", "", false, -1};
        staff[2] = {2, "Frank",  "Housekeeper",  "", "", false, -1};
        staff[3] = {3, "Grace",  "Housekeeper",  "", "", false, -1};
        staff[4] = {4, "Henry",  "Chef",          "", "", false, -1};
        staff[5] = {5, "Iris",   "Maintenance",  "", "", false, -1};

        restaurant = {60, 0};
    }
};

// ─── Main ─────────────────────────────────────────────────────────────────────

int main() {
    std::cout << "=== Hotel Management System (Traditional Architecture) ===\n\n";

    HotelSystem hotel;

    // Morning: staff shifts
    std::cout << "-- Morning Staff Shifts --\n";
    hotel.updateStaffShift(1, "07:00", "15:00");  // Receptionist
    hotel.updateStaffShift(2, "08:00", "16:00");  // Housekeeper floor 1
    hotel.updateStaffShift(3, "08:00", "16:00");  // Housekeeper floor 2
    hotel.updateStaffShift(4, "06:00", "14:00");  // Chef
    hotel.updateStaffShift(5, "09:00", "17:00");  // Maintenance

    // Reservations
    std::cout << "\n-- Reservations --\n";
    hotel.reserveRoom(1, RoomType::SUITE,  "2026-07-15", "2026-07-18");
    hotel.reserveRoom(2, RoomType::DOUBLE, "2026-07-15", "2026-07-17");
    hotel.reserveRoom(3, RoomType::SINGLE, "2026-07-15", "2026-07-16");
    hotel.reserveRoom(4, RoomType::DOUBLE, "2026-07-15", "2026-07-19");

    // Cancel one
    std::cout << "\n-- Cancellation --\n";
    hotel.cancelReservation(3);

    // Check-ins
    std::cout << "\n-- Check-Ins --\n";
    hotel.checkInGuest(1);
    hotel.checkInGuest(2);
    hotel.checkInGuest(4);

    // Room service & maintenance
    std::cout << "\n-- Room Service & Maintenance --\n";
    hotel.orderRoomService(301, "Club sandwich, orange juice, cheesecake");
    hotel.orderRoomService(201, "Pasta, mineral water");
    hotel.handleMaintenanceRequest(202, "AC not cooling properly");

    // Restaurant
    std::cout << "\n-- Restaurant --\n";
    hotel.seatGuestsInRestaurant(12);
    hotel.seatGuestsInRestaurant(8);
    hotel.releaseRestaurantSeats(10);

    // Morning report
    hotel.generateDailyReport();

    // Afternoon: check-out, housekeeping
    std::cout << "-- Afternoon Check-Out & Housekeeping --\n";
    hotel.checkOutGuest(2);                       // room 201 → CLEANING
    hotel.assignHousekeepingToFloor(2, 2);        // Grace cleans floor 2
    hotel.assignHousekeepingToFloor(3, 1);        // Frank cleans floor 1

    // Evening report
    hotel.generateDailyReport();

    return 0;
}
