import type { LogEvent, SleepSession } from '../db/types';
import { fmtClockShort, fmtDuration, sinceISO } from '../lib/time';

interface Props {
  events: LogEvent[];
  openSleep?: SleepSession;
  now: number;
  dueSoonHours: number;
  onToggleSleep: () => void;
}

function lastOf(events: LogEvent[], type: LogEvent['type']): LogEvent | undefined {
  let latest: LogEvent | undefined;
  for (const e of events) {
    if (e.type === type && (!latest || new Date(e.at) > new Date(latest.at))) latest = e;
  }
  return latest;
}

export function StatusTiles({ events, openSleep, now, dueSoonHours, onToggleSleep }: Props) {
  const lastFeed = lastOf(events, 'feed');
  const lastDiaper = lastOf(events, 'diaper');

  const feedAgeH = lastFeed ? (now - new Date(lastFeed.at).getTime()) / 3_600_000 : 0;
  const dueSoon = !!lastFeed && feedAgeH >= dueSoonHours;
  // "warms toward" the threshold in the hour before it (spec §3a)
  const approaching = !!lastFeed && !dueSoon && feedAgeH >= dueSoonHours - 1;

  const asleep = !!openSleep;
  const sleepMs = openSleep ? now - new Date(openSleep.startAt).getTime() : 0;

  return (
    <div className="tiles">
      <div className={`tile${dueSoon ? ' tile--warn' : approaching ? ' tile--approaching' : ''}`}>
        <span className="tile__label">Last feed</span>
        <span className="tile__value tabular">{lastFeed ? sinceISO(lastFeed.at, now) : '—'}</span>
        <span className="tile__sub">
          {lastFeed ? (dueSoon ? 'due soon' : `at ${fmtClockShort(lastFeed.at)}`) : 'none yet'}
        </span>
      </div>

      <div className="tile">
        <span className="tile__label">Last diaper</span>
        <span className="tile__value tabular">
          {lastDiaper ? sinceISO(lastDiaper.at, now) : '—'}
        </span>
        <span className="tile__sub">
          {lastDiaper ? `at ${fmtClockShort(lastDiaper.at)}` : 'none yet'}
        </span>
      </div>

      <button
        type="button"
        className={`tile tile--sleep${asleep ? ' is-asleep' : ''}`}
        onClick={onToggleSleep}
        aria-label={asleep ? 'Tap to mark awake' : 'Tap to mark asleep'}
      >
        <span className="tile__sleepState">
          <span className="tile__label">Sleep</span>
          <span className="tile__sub">
            {asleep ? `asleep since ${fmtClockShort(openSleep!.startAt)} · tap = woke` : 'awake · tap = put down'}
          </span>
        </span>
        <span className={`tile__sleepTimer tabular${asleep ? '' : ' is-awake'}`}>
          {asleep ? fmtDuration(sleepMs) : 'Awake'}
        </span>
      </button>
    </div>
  );
}
