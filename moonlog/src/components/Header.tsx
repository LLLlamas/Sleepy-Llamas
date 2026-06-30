import { format } from 'date-fns';
import type { Baby, SleepSession } from '../db/types';
import { dayNumber, fmtClockLong, fmtDuration } from '../lib/time';

interface Props {
  baby: Baby;
  now: number;
  openSleep?: SleepSession;
}

export function Header({ baby, now, openSleep }: Props) {
  const asleep = !!openSleep;
  const sleepMs = openSleep ? now - new Date(openSleep.startAt).getTime() : 0;

  return (
    <header className="header">
      <div className="header__brand">
        <span className="moon" aria-hidden="true">
          🌙
        </span>
        Moonlog
      </div>
      <div className="header__center">
        <div className="header__name">
          {baby.name} · Day {dayNumber(baby.birthAt, now)}
        </div>
        <div className="header__datetime tabular">
          {format(new Date(now), 'EEE, MMM d')} · {fmtClockLong(now)}
        </div>
      </div>
      <div className={`header__state tabular${asleep ? ' is-asleep' : ' is-awake'}`}>
        {asleep ? `Asleep · ${fmtDuration(sleepMs)}` : 'Awake now'}
      </div>
    </header>
  );
}
