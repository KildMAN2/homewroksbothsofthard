#include <iostream>
#include <string>
#include "hotel_system.h"

static void run_demo() {
    HotelSystem hotel;
    std::cout << "===== Traditional Hotel Management System (Demo) =====\n\n";

    std::cout << "--- Adding Guests ---\n";
    hotel.addGuest(1, "Alice Johnson", "555-1001");
    std::cout << "  [addGuest] Alice Johnson (ID 1)\n";
    hotel.addGuest(2, "Bob Martinez", "555-1002");
    std::cout << "  [addGuest] Bob Martinez (ID 2)\n";
    hotel.addGuest(3, "Carol Smith", "555-1003");
    std::cout << "  [addGuest] Carol Smith (ID 3)\n\n";

    std::cout << "--- Adding Rooms ---\n";
    hotel.addRoom(101, RoomType::SINGLE, 80.0,  1);
    std::cout << "  [addRoom] Room 101 | SINGLE | Floor 1 | $80.00/night\n";
    hotel.addRoom(102, RoomType::SINGLE, 80.0,  1);
    std::cout << "  [addRoom] Room 102 | SINGLE | Floor 1 | $80.00/night\n";
    hotel.addRoom(201, RoomType::DOUBLE, 140.0, 2);
    std::cout << "  [addRoom] Room 201 | DOUBLE | Floor 2 | $140.00/night\n";
    hotel.addRoom(301, RoomType::SUITE,  300.0, 3);
    std::cout << "  [addRoom] Room 301 | SUITE  | Floor 3 | $300.00/night\n\n";

    hotel.displayAvailableRooms();

    std::cout << "\n--- Reservations ---\n";
    hotel.createReservation(1, 1, 101, "2024-06-01", "2024-06-05");
    std::cout << "  [createReservation] #1: Guest 1 -> Room 101 (2024-06-01 to 2024-06-05)\n";
    hotel.createReservation(2, 2, 201, "2024-06-01", "2024-06-03");
    std::cout << "  [createReservation] #2: Guest 2 -> Room 201 (2024-06-01 to 2024-06-03)\n";
    hotel.createReservation(3, 3, 301, "2024-06-01", "2024-06-07");
    std::cout << "  [createReservation] #3: Guest 3 -> Room 301 (2024-06-01 to 2024-06-07)\n";

    std::cout << "\n--- Cancel Reservation #3 ---\n";
    hotel.cancelReservation(3);
    std::cout << "  [cancelReservation] Reservation #3 cancelled\n";

    std::cout << "\n--- Check-ins ---\n";
    hotel.checkIn(1);
    std::cout << "  [checkIn] Reservation #1 (Alice in Room 101)\n";
    hotel.checkIn(2);
    std::cout << "  [checkIn] Reservation #2 (Bob in Room 201)\n\n";

    hotel.displayAvailableRooms();

    std::cout << "\n--- Payments ---\n";
    hotel.processPayment(1, 1, 320.0);
    std::cout << "  [processPayment] $320.00 for Reservation #1\n";
    hotel.processPayment(2, 2, 280.0);
    std::cout << "  [processPayment] $280.00 for Reservation #2\n";

    std::cout << "\n--- Check-out ---\n";
    hotel.checkOut(1);
    std::cout << "  [checkOut] Reservation #1 (Room 101 -> CLEANING)\n";

    std::cout << "\n--- Cleaning Task ---\n";
    hotel.assignCleaningTask(1, 101, 10);
    std::cout << "  [assignCleaningTask] Room 101 -> Staff #10 (Room -> AVAILABLE)\n\n";

    hotel.displayAvailableRooms();

    std::cout << "\n--- Maintenance ---\n";
    hotel.reportMaintenance(1, 201, "Broken AC", "MEDIUM");
    std::cout << "  [reportMaintenance] Room 201: Broken AC [MEDIUM]\n";

    std::cout << "\n===== Demo Complete =====\n";
}

static void run_benchmark() {
    HotelSystem hotel;

    for (int i = 1; i <= 10000; i++)
        hotel.addGuest(i, "Guest_" + std::to_string(i), "555-" + std::to_string(i));

    for (int i = 1; i <= 1000; i++) {
        RoomType t = (i % 3 == 0) ? RoomType::SUITE :
                     (i % 2 == 0) ? RoomType::DOUBLE : RoomType::SINGLE;
        hotel.addRoom(i, t, 80.0 + (i % 3) * 60.0, (i - 1) / 100 + 1);
    }

    int resId = 1, payId = 1, taskId = 1, maintId = 1;

    for (int round = 0; round < 10; round++) {
        int baseResId = resId;
        for (int i = 1; i <= 1000; i++) {
            int gId = ((round * 1000) + i - 1) % 10000 + 1;
            hotel.createReservation(resId++, gId, i, "2024-01-01", "2024-01-03");
        }
        for (int i = 0; i < 1000; i++) hotel.checkIn(baseResId + i);
        for (int i = 0; i < 1000; i++) hotel.processPayment(payId++, baseResId + i, 200.0);
        for (int i = 0; i < 1000; i++) hotel.checkOut(baseResId + i);
        for (int i = 1; i <= 1000; i++) hotel.assignCleaningTask(taskId++, i, (round % 5) + 1);
        for (int i = 1; i <= 500;  i++) hotel.reportMaintenance(maintId++, (i-1)%1000+1, "Issue", "MEDIUM");
    }
}

int main(int argc, char* argv[]) {
    if (argc > 1 && std::string(argv[1]) == "benchmark")
        run_benchmark();
    else
        run_demo();
    return 0;
}
