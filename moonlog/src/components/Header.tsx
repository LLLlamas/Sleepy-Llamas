import type { Baby, Shift } from '../db/types';
import { dayNumber, fmtClockShort, sinceISO } from '../lib/time';

interface Props {
  baby: Baby;
  shift: Shift;
  now: number;
}

export function Header({ baby, shift, now }: Props) {
  return (
    <header className="header">
      <div className="header__brand">
        <span className="moon" aria-hidden="true">
          🌙
        </span>
        Moonlog
      </div>
      <div className="header__baby">
        <div className="header__name">
          {baby.name} · Day {dayNumber(baby.birthAt, now)}
        </div>
        <div className="header__meta tabular">
          Shift {fmtClockShort(shift.startedAt)} · {sinceISO(shift.startedAt, now)}
        </div>
      </div>
    </header>
  );
}
