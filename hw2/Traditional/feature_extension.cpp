// Part 3 -- Feature Extension: Emergency Maintenance + Auto Room Reassignment
//
// Traditional Architecture Analysis:
//   To add this feature we had to MODIFY existing files:
//     hotel_system.h   <- new method declaration added
//     hotel_system.cpp <- new method implementation added
//   The method accesses private members (rooms_, reservations_, guests_) directly.
//   Consequence: HotelSystem grows with every new cross-cutting feature.

#include <iostream>
#include "hotel_system.h"

int main() {
    std::cout << "===== Traditional: Part 3 Feature Extension Demo =====\n\n";
    std::cout << "Feature: Emergency Maintenance + Automatic Room Reassignment\n";
    std::cout << "Cost: hotel_system.h and hotel_system.cpp were both modified.\n\n";

    HotelSystem hotel;

    hotel.addGuest(1, "Alice Johnson", "555-1001");
    hotel.addGuest(2, "Bob Martinez",  "555-1002");
    hotel.addRoom(101, RoomType::SINGLE, 80.0,  1);
    hotel.addRoom(102, RoomType::SINGLE, 80.0,  1);   // replacement room
    hotel.addRoom(201, RoomType::DOUBLE, 140.0, 2);
    hotel.createReservation(1, 1, 101, "2024-06-01", "2024-06-05");
    hotel.createReservation(2, 2, 201, "2024-06-01", "2024-06-03");
    hotel.checkIn(1);
    hotel.checkIn(2);

    std::cout << "Initial state:\n";
    hotel.displayAvailableRooms();

    std::cout << "\n--- Emergency: Pipe burst in Room 101 ---\n";
    hotel.emergencyMaintenance(1, 101, "Pipe burst -- water leak");

    std::cout << "\nState after emergency:\n";
    hotel.displayAvailableRooms();

    std::cout << "\n===== Extension Demo Complete =====\n";
    return 0;
}
