import { format } from 'date-fns';
import { fmtShortMin } from '../../lib/time';

const DAY = 24 * 60 * 60 * 1000;

interface TimeFieldProps {
  value: number; // ms
  onChange: (ms: number) => void;
}

function relHint(ms: number): string {
  const diff = Date.now() - ms;
  const mins = Math.round(Math.abs(diff) / 60000);
  if (mins < 1) return 'now';
  return diff > 0 ? `${fmtShortMin(mins)} ago` : `in ${fmtShortMin(mins)}`;
}

/**
 * Native time picker — on a phone this is the scroll wheel with AM/PM.
 * Keeps the date of the current value and only changes the clock time; if the
 * chosen time lands far in the future it's treated as the previous day, so
 * logging an 11:50pm event at 12:10am does the right thing.
 */
export function TimeField({ value, onChange }: TimeFieldProps) {
  const hhmm = format(new Date(value), 'HH:mm');

  const handle = (next: string) => {
    if (!next) return;
    const [h, m] = next.split(':').map(Number);
    if (Number.isNaN(h) || Number.isNaN(m)) return;
    const d = new Date(value);
    d.setHours(h, m, 0, 0);
    let ms = d.getTime();
    if (ms - Date.now() > 12 * 60 * 60 * 1000) ms -= DAY; // overnight roll-back
    onChange(ms);
  };

  return (
    <div className="sheet__field">
      <span className="field-label">Time</span>
      <div className="time-row">
        <input
          type="time"
          className="input time-input tabular"
          value={hhmm}
          onChange={(e) => handle(e.target.value)}
          aria-label="time"
        />
        <button type="button" className="time-now" onClick={() => onChange(Date.now())}>
          Now
        </button>
      </div>
      <p className="field__hint">{relHint(value)}</p>
    </div>
  );
}
