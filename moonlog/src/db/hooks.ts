import { useLiveQuery } from 'dexie-react-hooks';
import { db } from './db';
import { nowISO, uid } from '../lib/id';
import type {
  Baby,
  DiaperContents,
  FeedEvent,
  FeedMethod,
  LogEvent,
  NoteEvent,
  Shift,
  SleepSession,
  StoolColor,
} from './types';

// ---------------------------------------------------------------------------
// Reactive queries (undefined === still loading)
// ---------------------------------------------------------------------------
export function useBabies(): Baby[] | undefined {
  return useLiveQuery(() => db.babies.toArray(), []);
}

export function useActiveShifts(babyId?: string): Shift[] | undefined {
  return useLiveQuery(
    () =>
      babyId
        ? db.shifts.where('babyId').equals(babyId).filter((s) => !s.endedAt).toArray()
        : Promise.resolve<Shift[]>([]),
    [babyId],
  );
}

export function useEvents(shiftId?: string): LogEvent[] | undefined {
  return useLiveQuery(
    () =>
      shiftId
        ? (db.events.where('shiftId').equals(shiftId).sortBy('at') as Promise<LogEvent[]>)
        : Promise.resolve<LogEvent[]>([]),
    [shiftId],
  );
}

export function useSleepSessions(shiftId?: string): SleepSession[] | undefined {
  return useLiveQuery(
    () =>
      shiftId
        ? db.sleepSessions.where('shiftId').equals(shiftId).sortBy('startAt')
        : Promise.resolve<SleepSession[]>([]),
    [shiftId],
  );
}

export function useOpenSleep(shiftId?: string): SleepSession | undefined {
  return useLiveQuery(
    () =>
      shiftId
        ? db.sleepSessions.where('shiftId').equals(shiftId).filter((s) => !s.endAt).first()
        : Promise.resolve<SleepSession | undefined>(undefined),
    [shiftId],
  );
}

export function useRecentShifts(babyId?: string): Shift[] | undefined {
  return useLiveQuery(
    () =>
      babyId
        ? db.shifts
            .where('babyId')
            .equals(babyId)
            .sortBy('startedAt')
            .then((a) => a.reverse())
        : Promise.resolve<Shift[]>([]),
    [babyId],
  );
}

export function useLastFeedMethod(shiftId?: string): FeedMethod | undefined {
  return useLiveQuery(async () => {
    if (!shiftId) return undefined;
    const feeds = (await db.events
      .where('shiftId')
      .equals(shiftId)
      .filter((e) => e.type === 'feed')
      .sortBy('at')) as FeedEvent[];
    return feeds.length ? feeds[feeds.length - 1].method : undefined;
  }, [shiftId]);
}

// ---------------------------------------------------------------------------
// Baby + shift lifecycle
// ---------------------------------------------------------------------------
export async function createBaby(name: string, birthAt: string): Promise<Baby> {
  const baby: Baby = { id: uid(), name: name.trim(), birthAt };
  await db.babies.add(baby);
  return baby;
}

export async function updateBaby(id: string, patch: Partial<Omit<Baby, 'id'>>): Promise<void> {
  await db.babies.update(id, patch);
}

export async function ensureActiveShift(babyId: string, caregiver?: string): Promise<Shift> {
  const existing = await db.shifts
    .where('babyId')
    .equals(babyId)
    .filter((s) => !s.endedAt)
    .first();
  if (existing) return existing;
  const shift: Shift = { id: uid(), babyId, startedAt: nowISO(), caregiver };
  await db.shifts.add(shift);
  return shift;
}

export async function endShiftAndStartFresh(
  babyId: string,
  shiftId: string,
  caregiver?: string,
): Promise<Shift> {
  const shift: Shift = { id: uid(), babyId, startedAt: nowISO(), caregiver };
  // atomic so observers never see zero or two open shifts in between
  await db.transaction('rw', db.shifts, async () => {
    await db.shifts.update(shiftId, { endedAt: nowISO() });
    await db.shifts.add(shift);
  });
  return shift;
}

export async function updateShift(id: string, patch: Partial<Omit<Shift, 'id'>>): Promise<void> {
  await db.shifts.update(id, patch);
}

// ---------------------------------------------------------------------------
// Event logging
// ---------------------------------------------------------------------------
export async function addFeed(
  shiftId: string,
  data: { at: string; method: FeedMethod; amountMl?: number; durationMin?: number; note?: string },
): Promise<FeedEvent> {
  const ev: FeedEvent = { id: uid(), shiftId, type: 'feed', createdAt: nowISO(), ...data };
  await db.events.add(ev);
  return ev;
}

export async function addDiaper(
  shiftId: string,
  data: { at: string; contents: DiaperContents; stool?: StoolColor; note?: string },
): Promise<LogEvent> {
  const ev = { id: uid(), shiftId, type: 'diaper', createdAt: nowISO(), ...data } as LogEvent;
  await db.events.add(ev);
  return ev;
}

export async function addNote(
  shiftId: string,
  data: { at: string; text?: string; tags?: string[]; tempF?: number },
): Promise<NoteEvent> {
  const ev: NoteEvent = { id: uid(), shiftId, type: 'note', createdAt: nowISO(), ...data };
  await db.events.add(ev);
  return ev;
}

// apply a patch, deleting keys whose value is undefined so edited records have
// the same shape as freshly-created ones (no lingering `key: undefined`)
function applyPatch<T extends object>(target: T, patch: Partial<T>): void {
  const t = target as Record<string, unknown>;
  for (const [k, v] of Object.entries(patch)) {
    if (v === undefined) delete t[k];
    else t[k] = v;
  }
}

export async function updateEvent(id: string, patch: Partial<LogEvent>): Promise<void> {
  await db.events.where('id').equals(id).modify((e) => {
    applyPatch(e, patch as Partial<typeof e>);
  });
}

export async function deleteEvent(id: string): Promise<void> {
  await db.events.delete(id);
}

export async function restoreEvent(ev: LogEvent): Promise<void> {
  await db.events.put(ev);
}

// ---------------------------------------------------------------------------
// Sleep sessions
// ---------------------------------------------------------------------------
export type SleepToggleResult =
  | { action: 'opened'; id: string }
  | { action: 'closed'; id: string };

export async function toggleSleep(shiftId: string): Promise<SleepToggleResult> {
  const open = await db.sleepSessions
    .where('shiftId')
    .equals(shiftId)
    .filter((s) => !s.endAt)
    .first();
  if (open) {
    await db.sleepSessions.update(open.id, { endAt: nowISO() });
    return { action: 'closed', id: open.id };
  }
  const s: SleepSession = { id: uid(), shiftId, startAt: nowISO() };
  await db.sleepSessions.add(s);
  return { action: 'opened', id: s.id };
}

export async function undoSleepToggle(result: SleepToggleResult): Promise<void> {
  if (result.action === 'opened') {
    await db.sleepSessions.delete(result.id);
  } else {
    // reopen the session by removing endAt
    await db.sleepSessions.where('id').equals(result.id).modify((s) => {
      delete s.endAt;
    });
  }
}

export async function addManualSleep(
  shiftId: string,
  startAt: string,
  endAt?: string,
): Promise<SleepSession> {
  const s: SleepSession = { id: uid(), shiftId, startAt, endAt };
  await db.sleepSessions.add(s);
  return s;
}

export async function updateSleep(
  id: string,
  patch: Partial<Omit<SleepSession, 'id'>>,
): Promise<void> {
  await db.sleepSessions.where('id').equals(id).modify((s) => {
    applyPatch(s, patch);
  });
}

export async function deleteSleep(id: string): Promise<void> {
  await db.sleepSessions.delete(id);
}

export async function restoreSleep(session: SleepSession): Promise<void> {
  await db.sleepSessions.put(session);
}

// ---------------------------------------------------------------------------
// Data management
// ---------------------------------------------------------------------------
export async function exportJSON(): Promise<string> {
  const [babies, shifts, events, sleepSessions] = await Promise.all([
    db.babies.toArray(),
    db.shifts.toArray(),
    db.events.toArray(),
    db.sleepSessions.toArray(),
  ]);
  return JSON.stringify(
    { app: 'moonlog', version: 1, exportedAt: nowISO(), babies, shifts, events, sleepSessions },
    null,
    2,
  );
}

export async function clearShiftData(shiftId: string): Promise<void> {
  await db.transaction('rw', db.events, db.sleepSessions, async () => {
    await db.events.where('shiftId').equals(shiftId).delete();
    await db.sleepSessions.where('shiftId').equals(shiftId).delete();
  });
}

export async function clearAllData(): Promise<void> {
  await db.transaction('rw', db.babies, db.shifts, db.events, db.sleepSessions, async () => {
    await Promise.all([db.babies.clear(), db.shifts.clear(), db.events.clear(), db.sleepSessions.clear()]);
  });
}
