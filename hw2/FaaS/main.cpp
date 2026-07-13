#include <iostream>
#include <string>
#include "faas_functions.h"

static void run_demo() {
    HotelStorage s;
    std::cout << "===== FaaS Hotel Management System (Demo) =====\n\n";

    std::cout << "--- Adding Guests ---\n";
    add_guest({1, "Alice Johnson", "555-1001"}, s);
    std::cout << "  [add_guest] Alice Johnson (ID 1)\n";
    add_guest({2, "Bob Martinez", "555-1002"}, s);
    std::cout << "  [add_guest] Bob Martinez (ID 2)\n";
    add_guest({3, "Carol Smith", "555-1003"}, s);
    std::cout << "  [add_guest] Carol Smith (ID 3)\n\n";

    std::cout << "--- Adding Rooms ---\n";
    add_room({101, RoomType::SINGLE, 80.0,  1}, s);
    std::cout << "  [add_room] Room 101 | SINGLE | Floor 1 | $80.00/night\n";
    add_room({102, RoomType::SINGLE, 80.0,  1}, s);
    std::cout << "  [add_room] Room 102 | SINGLE | Floor 1 | $80.00/night\n";
    add_room({201, RoomType::DOUBLE, 140.0, 2}, s);
    std::cout << "  [add_room] Room 201 | DOUBLE | Floor 2 | $140.00/night\n";
    add_room({301, RoomType::SUITE,  300.0, 3}, s);
    std::cout << "  [add_room] Room 301 | SUITE  | Floor 3 | $300.00/night\n\n";

    display_available_rooms(s);

    std::cout << "\n--- Reservations ---\n";
    create_reservation({1, 1, 101, "2024-06-01", "2024-06-05"}, s);
    std::cout << "  [create_reservation] #1: Guest 1 -> Room 101 (2024-06-01 to 2024-06-05)\n";
    create_reservation({2, 2, 201, "2024-06-01", "2024-06-03"}, s);
    std::cout << "  [create_reservation] #2: Guest 2 -> Room 201 (2024-06-01 to 2024-06-03)\n";
    create_reservation({3, 3, 301, "2024-06-01", "2024-06-07"}, s);
    std::cout << "  [create_reservation] #3: Guest 3 -> Room 301 (2024-06-01 to 2024-06-07)\n";

    std::cout << "\n--- Cancel Reservation #3 ---\n";
    cancel_reservation({3}, s);
    std::cout << "  [cancel_reservation] Reservation #3 cancelled\n";

    std::cout << "\n--- Check-ins ---\n";
    check_in({1}, s);
    std::cout << "  [check_in] Reservation #1 (Alice in Room 101)\n";
    check_in({2}, s);
    std::cout << "  [check_in] Reservation #2 (Bob in Room 201)\n\n";

    display_available_rooms(s);

    std::cout << "\n--- Payments ---\n";
    process_payment({1, 1, 320.0}, s);
    std::cout << "  [process_payment] $320.00 for Reservation #1\n";
    process_payment({2, 2, 280.0}, s);
    std::cout << "  [process_payment] $280.00 for Reservation #2\n";

    std::cout << "\n--- Check-out ---\n";
    check_out({1}, s);
    std::cout << "  [check_out] Reservation #1 (Room 101 -> CLEANING)\n";

    std::cout << "\n--- Cleaning Task ---\n";
    assign_cleaning_task({1, 101, 10}, s);
    std::cout << "  [assign_cleaning_task] Room 101 -> Staff #10 (Room -> AVAILABLE)\n\n";

    display_available_rooms(s);

    std::cout << "\n--- Maintenance ---\n";
    report_maintenance({1, 201, "Broken AC", "MEDIUM"}, s);
    std::cout << "  [report_maintenance] Room 201: Broken AC [MEDIUM]\n";

    std::cout << "\n===== Demo Complete =====\n";
}

static void run_benchmark() {
    HotelStorage s;   // std::map storage -- no pre-allocation needed

    for (int i = 1; i <= 10000; i++)
        add_guest({i, "Guest_" + std::to_string(i), "555-" + std::to_string(i)}, s);

    for (int i = 1; i <= 1000; i++) {
        RoomType t = (i % 3 == 0) ? RoomType::SUITE :
                     (i % 2 == 0) ? RoomType::DOUBLE : RoomType::SINGLE;
        add_room({i, t, 80.0 + (i % 3) * 60.0, (i - 1) / 100 + 1}, s);
    }

    int resId = 1, payId = 1, taskId = 1, maintId = 1;

    for (int round = 0; round < 10; round++) {
        int baseResId = resId;
        for (int i = 1; i <= 1000; i++) {
            int gId = ((round * 1000) + i - 1) % 10000 + 1;
            create_reservation({resId++, gId, i, "2024-01-01", "2024-01-03"}, s);
        }
        for (int i = 0; i < 1000; i++) check_in({baseResId + i}, s);
        for (int i = 0; i < 1000; i++) process_payment({payId++, baseResId + i, 200.0}, s);
        for (int i = 0; i < 1000; i++) check_out({baseResId + i}, s);
        for (int i = 1; i <= 1000; i++) assign_cleaning_task({taskId++, i, (round % 5) + 1}, s);
        for (int i = 1; i <= 500;  i++) report_maintenance({maintId++, (i-1)%1000+1, "Issue", "MEDIUM"}, s);
    }
}

int main(int argc, char* argv[]) {
    if (argc > 1 && std::string(argv[1]) == "benchmark")
        run_benchmark();
    else
        run_demo();
    return 0;
}
