import type { LogEvent, SleepSession } from '../db/types';
import { fmtClockShort, fmtDuration, spanMinutes } from '../lib/time';

interface Props {
  events: LogEvent[];
  openSleep?: SleepSession;
  now: number;
  babyName: string;
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

function agoText(iso: string, now: number): string {
  const min = spanMinutes(iso, now);
  if (min < 1) return 'just now';
  if (min < 60) return `${min} min${min === 1 ? '' : 's'} ago`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return `${h} hr${h === 1 ? '' : 's'}${m ? ` ${m} min${m === 1 ? '' : 's'}` : ''} ago`;
}

function feedSubtext(feed: LogEvent | undefined, now: number): string {
  if (!feed) return 'none yet';
  const duration = feed.type === 'feed' && feed.durationMin ? `${feed.durationMin} min feed · ` : '';
  return `${duration}${agoText(feed.at, now)}`;
}

export function StatusTiles({ events, openSleep, now, babyName, dueSoonHours, onToggleSleep }: Props) {
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
      <button
        type="button"
        className={`tile tile--sleep${asleep ? ' is-asleep' : ' is-awake'}`}
        onClick={onToggleSleep}
        aria-label={asleep ? `${babyName} is sleeping. Tap to mark awake.` : `${babyName} is awake. Tap to mark asleep.`}
      >
        <span className="tile__sleepState">
          <span className="tile__label">Baby status</span>
          <span className="tile__sleepCopy">{asleep ? `${babyName} is asleep` : `${babyName} is awake`}</span>
          <span className={`tile__sub${asleep ? ' tile__sleepHint' : ''}`}>
            {asleep ? `Since ${fmtClockShort(openSleep!.startAt)} · tap when ${babyName} wakes` : `Tap when ${babyName} falls asleep`}
          </span>
        </span>
        <span className={`tile__sleepTimer tabular${asleep ? '' : ' is-awake'}`}>
          {asleep ? `Asleep ${fmtDuration(sleepMs)}` : 'Awake'}
        </span>
      </button>

      <div className={`tile${dueSoon ? ' tile--warn' : approaching ? ' tile--approaching' : ''}`}>
        <span className="tile__label">Last feed</span>
        <span className="tile__value tabular">{lastFeed ? fmtClockShort(lastFeed.at) : '—'}</span>
        <span className="tile__sub">
          {feedSubtext(lastFeed, now)}
        </span>
      </div>

      <div className="tile">
        <span className="tile__label">Last diaper</span>
        <span className="tile__value tabular">
          {lastDiaper ? fmtClockShort(lastDiaper.at) : '—'}
        </span>
        <span className="tile__sub">
          {lastDiaper ? agoText(lastDiaper.at, now) : 'none yet'}
        </span>
      </div>
    </div>
  );
}
