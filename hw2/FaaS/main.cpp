#include <iostream>
#include <string>
#include "faas_functions.h"

// Register all 10 handlers under their event name -- mirrors configuring
// triggers/routes on a real FaaS platform (API Gateway -> Lambda mapping).
static FaaSOrchestrator buildOrchestrator() {
    FaaSOrchestrator orch;
    orch.registerFunction("add_guest", add_guest);
    orch.registerFunction("add_room", add_room);
    orch.registerFunction("create_reservation", create_reservation);
    orch.registerFunction("cancel_reservation", cancel_reservation);
    orch.registerFunction("check_in", check_in);
    orch.registerFunction("check_out", check_out);
    orch.registerFunction("process_payment", process_payment);
    orch.registerFunction("assign_cleaning_task", assign_cleaning_task);
    orch.registerFunction("report_maintenance", report_maintenance);
    orch.registerFunction("display_available_rooms", display_available_rooms);
    return orch;
}

static void run_demo() {
    HotelStorage s;
    FaaSOrchestrator orch = buildOrchestrator();
    std::cout << "===== FaaS Hotel Management System (Demo) =====\n\n";

    std::cout << "--- Adding Guests ---\n";
    orch.invoke("add_guest", {{"id","1"},{"name","Alice Johnson"},{"phone","555-1001"}}, s);
    std::cout << "  [add_guest] Alice Johnson (ID 1)\n";
    orch.invoke("add_guest", {{"id","2"},{"name","Bob Martinez"},{"phone","555-1002"}}, s);
    std::cout << "  [add_guest] Bob Martinez (ID 2)\n";
    orch.invoke("add_guest", {{"id","3"},{"name","Carol Smith"},{"phone","555-1003"}}, s);
    std::cout << "  [add_guest] Carol Smith (ID 3)\n\n";

    std::cout << "--- Adding Rooms ---\n";
    orch.invoke("add_room", {{"id","101"},{"type","SINGLE"},{"price","80.0"},{"floor","1"}}, s);
    std::cout << "  [add_room] Room 101 | SINGLE | Floor 1 | $80.00/night\n";
    orch.invoke("add_room", {{"id","102"},{"type","SINGLE"},{"price","80.0"},{"floor","1"}}, s);
    std::cout << "  [add_room] Room 102 | SINGLE | Floor 1 | $80.00/night\n";
    orch.invoke("add_room", {{"id","201"},{"type","DOUBLE"},{"price","140.0"},{"floor","2"}}, s);
    std::cout << "  [add_room] Room 201 | DOUBLE | Floor 2 | $140.00/night\n";
    orch.invoke("add_room", {{"id","301"},{"type","SUITE"},{"price","300.0"},{"floor","3"}}, s);
    std::cout << "  [add_room] Room 301 | SUITE  | Floor 3 | $300.00/night\n\n";

    orch.invoke("display_available_rooms", {}, s);

    std::cout << "\n--- Reservations ---\n";
    orch.invoke("create_reservation", {{"id","1"},{"guestId","1"},{"roomId","101"},{"checkIn","2024-06-01"},{"checkOut","2024-06-05"}}, s);
    std::cout << "  [create_reservation] #1: Guest 1 -> Room 101 (2024-06-01 to 2024-06-05)\n";
    orch.invoke("create_reservation", {{"id","2"},{"guestId","2"},{"roomId","201"},{"checkIn","2024-06-01"},{"checkOut","2024-06-03"}}, s);
    std::cout << "  [create_reservation] #2: Guest 2 -> Room 201 (2024-06-01 to 2024-06-03)\n";
    orch.invoke("create_reservation", {{"id","3"},{"guestId","3"},{"roomId","301"},{"checkIn","2024-06-01"},{"checkOut","2024-06-07"}}, s);
    std::cout << "  [create_reservation] #3: Guest 3 -> Room 301 (2024-06-01 to 2024-06-07)\n";

    std::cout << "\n--- Cancel Reservation #3 ---\n";
    orch.invoke("cancel_reservation", {{"reservationId","3"}}, s);
    std::cout << "  [cancel_reservation] Reservation #3 cancelled\n";

    std::cout << "\n--- Check-ins ---\n";
    orch.invoke("check_in", {{"reservationId","1"}}, s);
    std::cout << "  [check_in] Reservation #1 (Alice in Room 101)\n";
    orch.invoke("check_in", {{"reservationId","2"}}, s);
    std::cout << "  [check_in] Reservation #2 (Bob in Room 201)\n\n";

    orch.invoke("display_available_rooms", {}, s);

    std::cout << "\n--- Payments ---\n";
    orch.invoke("process_payment", {{"id","1"},{"reservationId","1"},{"amount","320.0"}}, s);
    std::cout << "  [process_payment] $320.00 for Reservation #1\n";
    orch.invoke("process_payment", {{"id","2"},{"reservationId","2"},{"amount","280.0"}}, s);
    std::cout << "  [process_payment] $280.00 for Reservation #2\n";

    std::cout << "\n--- Check-out ---\n";
    orch.invoke("check_out", {{"reservationId","1"}}, s);
    std::cout << "  [check_out] Reservation #1 (Room 101 -> CLEANING)\n";

    std::cout << "\n--- Cleaning Task ---\n";
    orch.invoke("assign_cleaning_task", {{"id","1"},{"roomId","101"},{"staffId","10"}}, s);
    std::cout << "  [assign_cleaning_task] Room 101 -> Staff #10 (Room -> AVAILABLE)\n\n";

    orch.invoke("display_available_rooms", {}, s);

    std::cout << "\n--- Maintenance ---\n";
    orch.invoke("report_maintenance", {{"id","1"},{"roomId","201"},{"description","Broken AC"},{"priority","MEDIUM"}}, s);
    std::cout << "  [report_maintenance] Room 201: Broken AC [MEDIUM]\n";

    std::cout << "\n===== Demo Complete =====\n";
}

static void run_benchmark() {
    HotelStorage s;
    FaaSOrchestrator orch = buildOrchestrator();

    for (int i = 1; i <= 10000; i++)
        orch.invoke("add_guest",
            {{"id", std::to_string(i)},
             {"name", "Guest_" + std::to_string(i)},
             {"phone", "555-" + std::to_string(i)}}, s);

    for (int i = 1; i <= 1000; i++) {
        const char* type = (i % 3 == 0) ? "SUITE" : (i % 2 == 0) ? "DOUBLE" : "SINGLE";
        double price = 80.0 + (i % 3) * 60.0;
        int floor = (i - 1) / 100 + 1;
        orch.invoke("add_room",
            {{"id", std::to_string(i)},
             {"type", type},
             {"price", std::to_string(price)},
             {"floor", std::to_string(floor)}}, s);
    }

    int resId = 1, payId = 1, taskId = 1, maintId = 1;

    for (int round = 0; round < 10; round++) {
        int baseResId = resId;
        for (int i = 1; i <= 1000; i++) {
            int gId = ((round * 1000) + i - 1) % 10000 + 1;
            orch.invoke("create_reservation",
                {{"id", std::to_string(resId)},
                 {"guestId", std::to_string(gId)},
                 {"roomId", std::to_string(i)},
                 {"checkIn", "2024-01-01"},
                 {"checkOut", "2024-01-03"}}, s);
            resId++;
        }
        for (int i = 0; i < 1000; i++)
            orch.invoke("check_in", {{"reservationId", std::to_string(baseResId + i)}}, s);

        for (int i = 0; i < 1000; i++) {
            orch.invoke("process_payment",
                {{"id", std::to_string(payId)},
                 {"reservationId", std::to_string(baseResId + i)},
                 {"amount", "200.0"}}, s);
            payId++;
        }

        for (int i = 0; i < 1000; i++)
            orch.invoke("check_out", {{"reservationId", std::to_string(baseResId + i)}}, s);

        for (int i = 1; i <= 1000; i++) {
            orch.invoke("assign_cleaning_task",
                {{"id", std::to_string(taskId)},
                 {"roomId", std::to_string(i)},
                 {"staffId", std::to_string((round % 5) + 1)}}, s);
            taskId++;
        }

        for (int i = 1; i <= 500; i++) {
            orch.invoke("report_maintenance",
                {{"id", std::to_string(maintId)},
                 {"roomId", std::to_string((i - 1) % 1000 + 1)},
                 {"description", "Issue"},
                 {"priority", "MEDIUM"}}, s);
            maintId++;
        }
    }
}

int main(int argc, char* argv[]) {
    if (argc > 1 && std::string(argv[1]) == "benchmark")
        run_benchmark();
    else
        run_demo();
    return 0;
}
