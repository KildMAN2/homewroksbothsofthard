#pragma once
#include "storage.h"
#include <string>

// ─── Event types ─────────────────────────────────────────────────────────────
// Each function receives one typed event describing the requested action.

struct AddGuestEvent          { int id; std::string name; std::string phone; };
struct AddRoomEvent           { int id; RoomType type; double pricePerNight; int floor; };
struct CreateReservationEvent { int id; int guestId; int roomId;
                                std::string checkIn; std::string checkOut; };
struct CancelReservationEvent { int reservationId; };
struct CheckInEvent           { int reservationId; };
struct CheckOutEvent          { int reservationId; };
struct ProcessPaymentEvent    { int id; int reservationId; double amount; };
struct AssignCleaningTaskEvent{ int id; int roomId; int staffId; };
struct ReportMaintenanceEvent { int id; int roomId;
                                std::string description; std::string priority; };

// ─── Function declarations (implemented in faas_functions.cpp) ────────────────
bool add_guest            (const AddGuestEvent&           e, HotelStorage& s);
bool add_room             (const AddRoomEvent&            e, HotelStorage& s);
bool create_reservation   (const CreateReservationEvent&  e, HotelStorage& s);
bool cancel_reservation   (const CancelReservationEvent&  e, HotelStorage& s);
bool check_in             (const CheckInEvent&            e, HotelStorage& s);
bool check_out            (const CheckOutEvent&           e, HotelStorage& s);
bool process_payment      (const ProcessPaymentEvent&     e, HotelStorage& s);
bool assign_cleaning_task (const AssignCleaningTaskEvent& e, HotelStorage& s);
bool report_maintenance   (const ReportMaintenanceEvent&  e, HotelStorage& s);
void display_available_rooms(const HotelStorage& s);
