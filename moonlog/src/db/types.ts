// Canonical data model (spec §6). Amounts stored in mL; times as ISO 8601.
export type ISO = string;

export type FeedMethod =
  | 'breast-left'
  | 'breast-right'
  | 'bottle-breastmilk'
  | 'bottle-formula';

export type DiaperContents = 'wet' | 'dirty' | 'both';

export type StoolColor = 'meconium' | 'transitional' | 'green' | 'brown' | 'yellow';

export interface Baby {
  id: string;
  name: string;
  birthAt: ISO; // for Day N + age
}

export interface Shift {
  id: string;
  babyId: string;
  startedAt: ISO;
  endedAt?: ISO;
  caregiver?: string;
}

export interface FeedEvent {
  id: string;
  shiftId: string;
  type: 'feed';
  at: ISO;
  method: FeedMethod;
  amountMl?: number; // bottle only
  durationMin?: number;
  note?: string;
  createdAt: ISO;
}

export interface DiaperEvent {
  id: string;
  shiftId: string;
  type: 'diaper';
  at: ISO;
  contents: DiaperContents;
  stool?: StoolColor;
  note?: string;
  createdAt: ISO;
}

export interface NoteEvent {
  id: string;
  shiftId: string;
  type: 'note';
  at: ISO;
  text?: string;
  tags?: string[]; // 'spit-up' | 'fussy' | 'jaundice' | 'pumped' | 'temp' | custom
  tempF?: number; // present if a temperature was logged
  createdAt: ISO;
}

export type LogEvent = FeedEvent | DiaperEvent | NoteEvent;
export type LogEventType = LogEvent['type'];

// Sleep is a session, not a pair of events — cleaner totals + "asleep now?" check
export interface SleepSession {
  id: string;
  shiftId: string;
  startAt: ISO;
  endAt?: ISO; // open session => baby currently asleep
}
