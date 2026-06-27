import { differenceInMinutes, format } from 'date-fns';

const MS_DAY = 24 * 60 * 60 * 1000;

/** "Day N" — completed 24h periods since birth (a 3-day-old shows Day 3). */
export function dayNumber(birthAt: string, now: number): number {
  const ms = now - new Date(birthAt).getTime();
  return Math.max(0, Math.floor(ms / MS_DAY));
}

/** "Xh YYm" relative duration from a millisecond span. Pads minutes. */
export function fmtDuration(ms: number): string {
  if (ms < 0) ms = 0;
  const totalMin = Math.floor(ms / 60000);
  if (totalMin < 1) return 'just now';
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  if (h === 0) return `0h ${String(m).padStart(2, '0')}m`;
  return `${h}h ${String(m).padStart(2, '0')}m`;
}

/** Same shape but from a minute count (used by summary totals: "7h 20m"). */
export function fmtMinutes(totalMin: number): string {
  return fmtDuration(Math.max(0, Math.round(totalMin)) * 60000);
}

/** Span since an ISO timestamp, relative to `now` (ms). */
export function sinceISO(iso: string, now: number): string {
  return fmtDuration(now - new Date(iso).getTime());
}

/** "3:12a" — compact clock for timeline rows + header. */
export function fmtClockShort(iso: string | number): string {
  return format(new Date(iso), 'h:mmaaaaa');
}

/** "8:05 PM" — full clock for the shareable summary. */
export function fmtClockLong(iso: string | number): string {
  return format(new Date(iso), 'h:mm a');
}

export function minutesBetween(startIso: string, endIso: string | number): number {
  return differenceInMinutes(new Date(endIso), new Date(startIso));
}

/** Rounded, non-negative minute span — used for both timeline rows and totals
 * so a session's per-row duration matches the aggregate. */
export function spanMinutes(startIso: string, endIso: string | number): number {
  const ms = new Date(endIso).getTime() - new Date(startIso).getTime();
  return Math.max(0, Math.round(ms / 60000));
}

/** Whole-minute label like "18m" / "1h 5m" for inline durations. */
export function fmtShortMin(totalMin: number): string {
  if (totalMin < 0) totalMin = 0;
  if (totalMin < 60) return `${totalMin}m`;
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  return m ? `${h}h ${m}m` : `${h}h`;
}
