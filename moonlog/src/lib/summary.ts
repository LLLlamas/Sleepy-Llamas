import { format } from 'date-fns';
import type {
  Baby,
  FeedEvent,
  FeedMethod,
  LogEvent,
  NoteEvent,
  Shift,
  SleepSession,
  StoolColor,
} from '../db/types';
import { dayNumber, fmtClockLong, fmtClockShort, fmtShortMin } from './time';
import { formatAmount, type Unit } from './units';
import { STOOL_LABEL, isBottle, tagLabel } from './labels';

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

const WARM_METHOD: Record<FeedMethod, string> = {
  'breast-left': 'left breast',
  'breast-right': 'right breast',
  'bottle-breastmilk': 'bottle, breastmilk',
  'bottle-formula': 'bottle, formula',
};

function warmFeedLine(ev: FeedEvent, unit: Unit): string {
  const bits: string[] = [];
  if (isBottle(ev.method) && ev.amountMl != null) bits.push(formatAmount(ev.amountMl, unit));
  if (ev.durationMin) bits.push(`${ev.durationMin} min`);
  return bits.length ? `${WARM_METHOD[ev.method]} — ${bits.join(', ')}` : WARM_METHOD[ev.method];
}

function noteSummaryLine(ev: NoteEvent): string {
  const parts: string[] = [];
  if (ev.text) parts.push(ev.text);
  if (ev.tempF != null) parts.push(`temp ${ev.tempF}°F`);
  if (ev.tags?.length) {
    const extra = ev.tags.filter((t) => t !== 'temp').map(tagLabel);
    if (extra.length) parts.push(extra.join(', '));
  }
  return parts.join(' · ') || 'Note';
}

/**
 * Warm, human-readable night summary for the morning handoff. Stays plain text
 * (emoji included) so it pastes cleanly into Messages / email / Notes.
 */
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
  const dateLabel = format(new Date(shift.startedAt), 'EEE, MMM d');
  const start = fmtClockLong(shift.startedAt);
  const end = fmtClockLong(shift.endedAt ?? now);
  const current = fmtClockLong(now);

  const L: string[] = [];
  L.push(`🌙 ${baby.name}'s night · Day ${day}`);
  L.push(`${dateLabel} · current time ${current}`);
  L.push(`Shift started at ${start} · summary through ${end}`);
  if (shift.caregiver) L.push(`Cared for by ${shift.caregiver}`);
  L.push('');

  // Feeds
  const ozLabel = totals.feedMl ? ` (about ${formatAmount(totals.feedMl, unit)})` : '';
  L.push(`🍼  Feeds · ${totals.feeds}${ozLabel}`);
  for (const ev of sorted) {
    if (ev.type === 'feed') L.push(`     ${fmtClockShort(ev.at)}  ${warmFeedLine(ev, unit)}`);
  }
  L.push('');

  // Diapers
  L.push(`🧷  Diapers · ${totals.diapers}  (${totals.wet} wet, ${totals.dirty} dirty)`);
  const prog = totals.stoolProgression.map((s) => STOOL_LABEL[s].toLowerCase()).join(' → ');
  if (prog) L.push(`     stool: ${prog}`);
  L.push('');

  // Sleep
  L.push(
    `😴  Sleep · ${fmtShortMin(totals.sleepMin)} over ${totals.stretches} stretch${
      totals.stretches === 1 ? '' : 'es'
    }`,
  );
  if (totals.longestMin) L.push(`     longest was ${fmtShortMin(totals.longestMin)}`);
  L.push('');

  // Notes
  if (totals.notes) {
    L.push('📝  Notes');
    for (const ev of sorted) {
      if (ev.type === 'note') L.push(`     ${fmtClockShort(ev.at)}  ${noteSummaryLine(ev)}`);
    }
    L.push('');
  }

  // Warm sign-off
  if (shift.caregiver) {
    L.push('With care,');
    L.push(`${shift.caregiver} 🌙`);
  } else {
    L.push('🌙 logged with Moonlog');
  }
  return L.join('\n');
}
