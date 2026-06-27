import Dexie, { type Table } from 'dexie';
import type { Baby, Shift, LogEvent, SleepSession } from './types';

// IndexedDB-backed, offline-first store. Nothing here ever touches the network.
export class MoonlogDB extends Dexie {
  babies!: Table<Baby, string>;
  shifts!: Table<Shift, string>;
  events!: Table<LogEvent, string>;
  sleepSessions!: Table<SleepSession, string>;

  constructor() {
    super('moonlog');
    this.version(1).stores({
      babies: 'id',
      shifts: 'id, babyId, startedAt',
      events: 'id, shiftId, type, at',
      sleepSessions: 'id, shiftId, startAt',
    });
  }
}

export const db = new MoonlogDB();
