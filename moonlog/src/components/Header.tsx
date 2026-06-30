import { format, isSameDay } from 'date-fns';
import type { Baby, Shift } from '../db/types';

interface Props {
  baby: Baby;
  shift: Shift;
  now: number;
  onEditShiftStart: () => void;
}

const PencilIcon = () => (
  <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M12 20h9" />
    <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z" />
  </svg>
);

export function Header({ baby, shift, now, onEditShiftStart }: Props) {
  const startD = new Date(shift.startedAt);
  // After midnight the calendar date no longer matches the night the shift began —
  // surface that gently so a 3am caregiver isn't thrown by the date.
  const dayChanged = !isSameDay(now, startD);

  return (
    <header className="header">
      <div className="header__left">
        <div className="header__brand">
          <span className="moon" aria-hidden="true">🌙</span>
          Moonlog
        </div>
        <button
          type="button"
          className="header__shift"
          onClick={onEditShiftStart}
          aria-label={`Shift started ${format(startD, 'h:mm a')} — tap to adjust`}
        >
          <span className="header__shift-text tabular">Shift · {format(startD, 'h:mm a')}</span>
          <span className="header__edit" aria-hidden="true"><PencilIcon /></span>
        </button>
      </div>

      <div className="header__baby">
        <div className="header__name">{baby.name}</div>
        <div className={`header__when tabular${dayChanged ? ' is-daychange' : ''}`}>
          {format(now, 'EEE, MMM d')} · {format(now, 'h:mm a')}
        </div>
      </div>
    </header>
  );
}
