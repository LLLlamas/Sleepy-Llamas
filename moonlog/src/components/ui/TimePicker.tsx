import { useCallback, useEffect, useRef, useState } from 'react';
import { format, isSameDay } from 'date-fns';
import { fmtShortMin } from '../../lib/time';

interface TimePickerProps {
  value: number; // ms
  onChange: (ms: number) => void;
  /** accessible name for the collapsed trigger */
  ariaLabel?: string;
  /** reference instant for the relative hint + day-change highlight (default: now) */
  referenceMs?: number;
  /** show the "Now" quick-set (default true) */
  showNow?: boolean;
  /** open the panel on mount (default false → tap to reveal) */
  defaultOpen?: boolean;
}

const MIN_STEP = 1;

/** "in 12m" / "8m ago" / "now" relative to the reference instant. */
function relHint(ms: number, ref: number): string {
  const diff = ref - ms;
  const mins = Math.round(Math.abs(diff) / 60000);
  if (mins < 1) return 'now';
  return diff > 0 ? `${fmtShortMin(mins)} ago` : `in ${fmtShortMin(mins)}`;
}

/**
 * Press-and-hold to repeat: a single tap nudges once; holding accelerates so a
 * bleary caregiver can run the clock back an hour without 60 taps. Pointer-based
 * so it works with touch + mouse and cancels cleanly on lift/leave.
 */
function useHoldRepeat(fn: () => void) {
  const timers = useRef<{ delay?: number; tick?: number }>({});
  const fnRef = useRef(fn);
  fnRef.current = fn;

  const stop = useCallback(() => {
    if (timers.current.delay) window.clearTimeout(timers.current.delay);
    if (timers.current.tick) window.clearInterval(timers.current.tick);
    timers.current = {};
  }, []);

  const start = useCallback(() => {
    fnRef.current();
    timers.current.delay = window.setTimeout(() => {
      timers.current.tick = window.setInterval(() => fnRef.current(), 90);
    }, 420);
  }, []);

  useEffect(() => stop, [stop]);

  return {
    onPointerDown: (e: React.PointerEvent) => {
      e.preventDefault();
      start();
    },
    onPointerUp: stop,
    onPointerLeave: stop,
    onPointerCancel: stop,
  };
}

/**
 * Compact, brand-themed time picker. Collapsed it's a tappable pill showing the
 * time with a tiny edit cue; tapping reveals hour/minute/period nudgers — no
 * native scroll-wheel, no calendar. Edits the clock time and keeps the date,
 * so nudging past midnight rolls the day and surfaces a day-change highlight.
 */
export function TimePicker({
  value,
  onChange,
  ariaLabel = 'time',
  referenceMs,
  showNow = true,
  defaultOpen = false,
}: TimePickerProps) {
  const [open, setOpen] = useState(defaultOpen);
  const ref = referenceMs ?? Date.now();
  const d = new Date(value);

  const nudge = (field: 'h' | 'm', delta: number) => {
    const next = new Date(value);
    if (field === 'h') next.setHours(next.getHours() + delta);
    else next.setMinutes(next.getMinutes() + delta);
    next.setSeconds(0, 0);
    onChange(next.getTime());
  };
  const togglePeriod = () => {
    const next = new Date(value);
    const h = next.getHours();
    next.setHours(h < 12 ? h + 12 : h - 12);
    next.setSeconds(0, 0);
    onChange(next.getTime());
  };

  const decHour = useHoldRepeat(() => nudge('h', -1));
  const incHour = useHoldRepeat(() => nudge('h', 1));
  const decMin = useHoldRepeat(() => nudge('m', -MIN_STEP));
  const incMin = useHoldRepeat(() => nudge('m', MIN_STEP));

  const isPM = d.getHours() >= 12;
  const sameDay = isSameDay(d, new Date(ref));
  // signed day delta relative to the reference (so we can say +1 / prev day)
  const dayDelta = Math.round(
    (new Date(d).setHours(0, 0, 0, 0) - new Date(ref).setHours(0, 0, 0, 0)) / 86400000,
  );

  return (
    <div className={`timepick${open ? ' is-open' : ''}`}>
      <button
        type="button"
        className="timepick__trigger"
        aria-label={`${ariaLabel}: ${format(d, 'h:mm a')} — tap to change`}
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
      >
        <span className="timepick__time tabular">{format(d, 'h:mm')}</span>
        <span className="timepick__period">{isPM ? 'PM' : 'AM'}</span>
        {!sameDay && (
          <span className="timepick__daychip" title="Different day">
            {format(d, 'EEE, MMM d')}
            {dayDelta === 1 ? ' · next day' : dayDelta === -1 ? ' · prev day' : ''}
          </span>
        )}
        <span className="timepick__edit" aria-hidden="true">
          <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 20h9" />
            <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z" />
          </svg>
          {open ? 'done' : 'edit'}
        </span>
      </button>

      {open && (
        <div className="timepick__panel" role="group" aria-label={`Set ${ariaLabel}`}>
          <div className="timepick__readout tabular">
            {format(d, 'h:mm')} <span className="timepick__readout-period">{isPM ? 'PM' : 'AM'}</span>
          </div>

          <div className="timepick__rows">
            <div className="timepick__unit">
              <span className="timepick__unit-label">Hour</span>
              <div className="timepick__nudge">
                <button type="button" className="timepick__btn" aria-label="hour down" {...decHour}>−</button>
                <span className="timepick__num tabular">{format(d, 'h')}</span>
                <button type="button" className="timepick__btn" aria-label="hour up" {...incHour}>+</button>
              </div>
            </div>

            <div className="timepick__unit">
              <span className="timepick__unit-label">Minute</span>
              <div className="timepick__nudge">
                <button type="button" className="timepick__btn" aria-label="minute down" {...decMin}>−</button>
                <span className="timepick__num tabular">{format(d, 'mm')}</span>
                <button type="button" className="timepick__btn" aria-label="minute up" {...incMin}>+</button>
              </div>
            </div>
          </div>

          <div className="timepick__foot">
            <div className="timepick__ampm" role="group" aria-label="AM or PM">
              <button
                type="button"
                className={`timepick__seg${!isPM ? ' is-on' : ''}`}
                aria-pressed={!isPM}
                onClick={() => isPM && togglePeriod()}
              >
                AM
              </button>
              <button
                type="button"
                className={`timepick__seg${isPM ? ' is-on' : ''}`}
                aria-pressed={isPM}
                onClick={() => !isPM && togglePeriod()}
              >
                PM
              </button>
            </div>
            {showNow && (
              <button
                type="button"
                className="timepick__now"
                onClick={() => onChange(Date.now())}
              >
                Now
              </button>
            )}
          </div>

          <p className="timepick__hint">{relHint(value, ref)}</p>
        </div>
      )}
    </div>
  );
}
