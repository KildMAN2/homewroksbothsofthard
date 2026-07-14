#pragma once
#include "storage.h"
#include <string>
#include <map>
#include <functional>

// ─── Generic event/result payloads ────────────────────────────────────────────
// A real FaaS platform (AWS Lambda, Azure Functions, ...) invokes a function
// with a serialized payload (typically JSON) and gets back a serialized
// result. We model that faithfully with string-keyed maps: every argument is
// marshaled to a string on the caller side and parsed back inside the
// handler -- this is real, unavoidable FaaS overhead, not a data-structure
// trick. HotelStorage itself stays a std::map (same indexed store as
// Traditional) so the benchmark isolates the cost of the FaaS invocation
// model, not the cost of a slower collection type.
using EventData  = std::map<std::string, std::string>;
using ResultData = std::map<std::string, std::string>;

// Signature every FaaS handler implements.
using FaaSFn = std::function<ResultData(const EventData&, HotelStorage&)>;

// ─── The 11 independent function handlers ─────────────────────────────────────
ResultData add_guest             (const EventData& e, HotelStorage& s);
ResultData add_room              (const EventData& e, HotelStorage& s);
// Reserves the room for [checkIn, checkOut) if no OTHER active reservation for
// that room overlaps the requested date range (see models.h::overlaps).
ResultData create_reservation    (const EventData& e, HotelStorage& s);
ResultData cancel_reservation    (const EventData& e, HotelStorage& s);
ResultData check_in              (const EventData& e, HotelStorage& s);
ResultData check_out             (const EventData& e, HotelStorage& s);
ResultData process_payment       (const EventData& e, HotelStorage& s);
// Assigns a cleaning task to a room currently CLEANING. The room stays
// CLEANING until complete_cleaning_task() runs -- assigning a task must not
// itself mean the cleaning is already done.
ResultData assign_cleaning_task  (const EventData& e, HotelStorage& s);
// Marks a previously assigned cleaning task as finished and frees the room.
ResultData complete_cleaning_task(const EventData& e, HotelStorage& s);
ResultData report_maintenance    (const EventData& e, HotelStorage& s);
ResultData display_available_rooms(const EventData& e, HotelStorage& s);

// ─── Orchestrator ──────────────────────────────────────────────────────────────
// Models the API-Gateway / event-router layer of a real FaaS platform:
// handlers are registered under a NAME and invoked through a string-keyed
// lookup + std::function indirection, instead of being called directly.
class FaaSOrchestrator {
public:
    void registerFunction(const std::string& name, FaaSFn fn);
    ResultData invoke(const std::string& name, const EventData& event, HotelStorage& storage);

private:
    std::map<std::string, FaaSFn> registry_;
};
