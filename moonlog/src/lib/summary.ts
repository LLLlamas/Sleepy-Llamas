import type { Baby, LogEvent, Shift, SleepSession, StoolColor } from '../db/types';
import { dayNumber, fmtClockLong, fmtShortMin } from './time';
import { displayAmount, type Unit } from './units';
import { METHOD_LABEL_SHORT, STOOL_LABEL, isBottle, tagLabel } from './labels';

export interface Totals {
  feeds: number;
  feedMl: number;
  diapers: number;
  wet: number;
  dirty: number;
  stoolProgression: StoolColor[];
  sleepMin: number;
  stretches: number;
  longestMin: number;
  notes: number;
}

function sessionMinutes(s: SleepSession, now: number): number {
  const end = s.endAt ? new Date(s.endAt).getTime() : now;
  return Math.max(0, Math.round((end - new Date(s.startAt).getTime()) / 60000));
}

export function computeTotals(
  events: LogEvent[],
  sessions: SleepSession[],
  now: number,
): Totals {
  const sorted = [...events].sort(
    (a, b) => new Date(a.at).getTime() - new Date(b.at).getTime(),
  );
  let feeds = 0,
    feedMl = 0,
    diapers = 0,
    wet = 0,
    dirty = 0,
    notes = 0;
  const stool: StoolColor[] = [];
  for (const ev of sorted) {
    if (ev.type === 'feed') {
      feeds++;
      if (ev.amountMl) feedMl += ev.amountMl;
    } else if (ev.type === 'diaper') {
      diapers++;
      if (ev.contents === 'wet' || ev.contents === 'both') wet++;
      if (ev.contents === 'dirty' || ev.contents === 'both') dirty++;
      if (ev.stool && !stool.includes(ev.stool)) stool.push(ev.stool);
    } else {
      notes++;
    }
  }
  const durations = sessions.map((s) => sessionMinutes(s, now));
  return {
    feeds,
    feedMl,
    diapers,
    wet,
    dirty,
    stoolProgression: stool,
    sleepMin: durations.reduce((a, b) => a + b, 0),
    stretches: sessions.length,
    longestMin: durations.length ? Math.max(...durations) : 0,
    notes,
  };
}

function amountText(ml: number, unit: Unit): string {
  const v = displayAmount(ml, unit);
  const num = v % 1 === 0 ? String(v) : v.toFixed(1);
  return unit === 'oz' ? `${num}oz` : `${num}ml`;
}

function feedSummaryLine(ev: Extract<LogEvent, { type: 'feed' }>, unit: Unit): string {
  let s = METHOD_LABEL_SHORT[ev.method];
  if (isBottle(ev.method) && ev.amountMl != null) s += ` ${amountText(ev.amountMl, unit)}`;
  if (ev.durationMin) s += ` (${ev.durationMin}m)`;
  return s;
}

function noteSummaryLine(ev: Extract<LogEvent, { type: 'note' }>): string {
  const parts: string[] = [];
  if (ev.text) parts.push(ev.text);
  if (ev.tempF != null) parts.push(`Temp ${ev.tempF}°F`);
  if (ev.tags?.length) {
    const extra = ev.tags.filter((t) => t !== 'temp').map(tagLabel);
    if (extra.length) parts.push(extra.join(', '));
  }
  return parts.join(' · ') || 'Note';
}

/** Plain-text night summary matching spec §7, for clipboard / Web Share. */
export function buildSummaryText(
  baby: Baby,
  shift: Shift,
  events: LogEvent[],
  sessions: SleepSession[],
  unit: Unit,
  now: number,
): string {
  const totals = computeTotals(events, sessions, now);
  const sorted = [...events].sort(
    (a, b) => new Date(a.at).getTime() - new Date(b.at).getTime(),
  );
  const day = dayNumber(baby.birthAt, now);
  const start = fmtClockLong(shift.startedAt);
  const end = fmtClockLong(shift.endedAt ?? now);

  const lines: string[] = [];
  lines.push(`🌙 Night summary — ${baby.name}, Day ${day}`);
  const cg = shift.caregiver ? ` (caregiver: ${shift.caregiver})` : '';
  lines.push(`Shift: ${start} – ${end}${cg}`);
  lines.push('');

  const ozTotal = displayAmount(totals.feedMl, unit);
  const totalAmt = totals.feedMl
    ? unit === 'oz'
      ? ` (~${ozTotal % 1 === 0 ? ozTotal : ozTotal.toFixed(1)} oz)`
      : ` (~${ozTotal} ml)`
    : '';
  lines.push(`FEEDS — ${totals.feeds}${totalAmt}`);
  for (const ev of sorted) {
    if (ev.type === 'feed') {
      lines.push(`  ${fmtClockLong(ev.at)}  ${feedSummaryLine(ev, unit)}`);
    }
  }

  const progression = totals.stoolProgression.map((s) => STOOL_LABEL[s].toLowerCase()).join(' → ');
  const stoolPart = progression ? ` · stool ${progression}` : '';
  lines.push(`DIAPERS — ${totals.diapers} (${totals.wet} wet, ${totals.dirty} dirty)${stoolPart}`);

  lines.push(
    `SLEEP — ${fmtShortMin(totals.sleepMin)} across ${totals.stretches} stretch${
      totals.stretches === 1 ? '' : 'es'
    }${totals.longestMin ? ` (longest ${fmtShortMin(totals.longestMin)})` : ''}`,
  );

  if (totals.notes) {
    lines.push('NOTES');
    for (const ev of sorted) {
      if (ev.type === 'note') {
        lines.push(`  ${fmtClockLong(ev.at)}  ${noteSummaryLine(ev)}`);
      }
    }
  }

  lines.push('');
  lines.push('— logged with Moonlog');
  return lines.join('\n');
}
