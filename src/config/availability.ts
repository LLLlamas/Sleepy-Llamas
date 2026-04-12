// ============================================================================
// AVAILABILITY CONFIG — owner-editable date status map.
//
// Dates NOT listed here default to "available". Only add dates that are
// booked or unavailable. Format: "YYYY-MM-DD".
//
// Example:
//   "2026-04-20": "booked",       // client reserved this night
//   "2026-04-25": "unavailable",  // owner PTO / personal
//
// The Availability calendar reads this and renders it visually.
// ============================================================================

export type DayStatus = 'booked' | 'unavailable' | 'available';

export const availability: Record<string, DayStatus> = {
  // TODO: add real bookings and unavailable dates here.
  // A few sample entries so the calendar has something to show out-of-the-box —
  // remove or replace them before going live.
  '2026-04-14': 'booked',
  '2026-04-15': 'booked',
  '2026-04-22': 'unavailable',
  '2026-04-28': 'booked',
  '2026-05-03': 'booked',
  '2026-05-10': 'unavailable',
  '2026-05-17': 'booked',
};

/** Number of months the calendar can browse into the future. */
export const MAX_MONTHS_AHEAD = 3;
