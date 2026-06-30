import { useEffect, useMemo, useRef } from 'react';
import { fmtShortMin } from '../../lib/time';

interface DurationScrollerProps {
  value: number;
  onChange: (minutes: number) => void;
  maxHours?: number;
  minuteStep?: number;
  zeroLabel?: string;
  ariaLabel?: string;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function splitDuration(totalMinutes: number, step: number, maxHours: number) {
  const maxMinutes = maxHours * 60;
  const clamped = clamp(Math.round(totalMinutes), 0, maxMinutes);
  let hours = Math.floor(clamped / 60);
  let minutes = clamped % 60;

  minutes = Math.round(minutes / step) * step;
  if (minutes >= 60) {
    hours += 1;
    minutes = 0;
  }
  if (hours >= maxHours) {
    hours = maxHours;
    minutes = 0;
  }

  return { hours, minutes };
}

export function DurationScroller({
  value,
  onChange,
  maxHours = 12,
  minuteStep = 5,
  zeroLabel = 'No duration',
  ariaLabel = 'Duration',
}: DurationScrollerProps) {
  const step = clamp(Math.round(minuteStep), 1, 30);
  const hourOptions = useMemo(
    () => Array.from({ length: maxHours + 1 }, (_, i) => i),
    [maxHours],
  );
  const minuteOptions = useMemo(
    () => Array.from({ length: Math.ceil(60 / step) }, (_, i) => i * step).filter((m) => m < 60),
    [step],
  );

  const { hours, minutes } = splitDuration(value, step, maxHours);
  const hourRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const minuteRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const minuteIndex = Math.max(0, minuteOptions.indexOf(minutes));

  useEffect(() => {
    hourRefs.current[hours]?.scrollIntoView({ block: 'center' });
    minuteRefs.current[minuteIndex]?.scrollIntoView({ block: 'center' });
  }, [hours, minuteIndex]);

  const setParts = (nextHours: number, nextMinutes: number) => {
    onChange(clamp(nextHours * 60 + nextMinutes, 0, maxHours * 60));
  };

  const readout = value > 0 ? fmtShortMin(hours * 60 + minutes) : zeroLabel;

  return (
    <div className="duration-scroller" role="group" aria-label={ariaLabel}>
      <div className="duration-scroller__readout tabular">{readout}</div>
      <div className="duration-scroller__wheels">
        <div className="duration-wheel" aria-label="Hours">
          <div className="duration-wheel__unit">hours</div>
          {hourOptions.map((h) => (
            <button
              key={h}
              ref={(el) => {
                hourRefs.current[h] = el;
              }}
              type="button"
              className={`duration-wheel__option${h === hours ? ' is-selected' : ''}`}
              aria-pressed={h === hours}
              onClick={() => setParts(h, minutes)}
            >
              {h}
            </button>
          ))}
        </div>
        <div className="duration-wheel" aria-label="Minutes">
          <div className="duration-wheel__unit">min</div>
          {minuteOptions.map((m, i) => (
            <button
              key={m}
              ref={(el) => {
                minuteRefs.current[i] = el;
              }}
              type="button"
              className={`duration-wheel__option${m === minutes ? ' is-selected' : ''}`}
              aria-pressed={m === minutes}
              onClick={() => setParts(hours, m)}
            >
              {String(m).padStart(2, '0')}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
