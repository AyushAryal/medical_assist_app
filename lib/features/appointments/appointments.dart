/// Public surface of the appointments module.
///
/// Booking, rescheduling and the schedule view. Other features (the dashboard's
/// next-up card, patient booking) import THIS file, not the internals.
library;

export 'appointment_tile.dart' show AppointmentTile;
export 'book_appointment_sheet.dart' show BookAppointmentSheet;
export 'schedule_screen.dart' show ScheduleScreen;
