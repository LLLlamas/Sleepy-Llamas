import { useRef } from 'react';

interface Props {
  isAsleep: boolean;
  babyName: string;
  onFeed: () => void;
  onDiaper: () => void;
  onSleepToggle: () => void;
  onSleepManual: () => void;
  onNote: () => void;
}

const LONG_PRESS_MS = 500;

export function QuickActions({
  isAsleep,
  babyName,
  onFeed,
  onDiaper,
  onSleepToggle,
  onSleepManual,
  onNote,
}: Props) {
  const timer = useRef<number | undefined>(undefined);
  const longFired = useRef(false);

  const startPress = () => {
    longFired.current = false;
    timer.current = window.setTimeout(() => {
      longFired.current = true;
      onSleepManual();
    }, LONG_PRESS_MS);
  };
  const endPress = () => {
    if (timer.current) window.clearTimeout(timer.current);
  };
  const onSleepClick = () => {
    if (longFired.current) {
      longFired.current = false;
      return; // long-press already handled (manual entry)
    }
    onSleepToggle();
  };

  return (
    <div className="quick-actions">
      <button type="button" className="qa" onClick={onFeed}>
        <span className="qa__icon" aria-hidden="true">🍼</span>
        <span className="qa__label">Feed</span>
      </button>
      <button type="button" className="qa" onClick={onDiaper}>
        <span className="qa__icon" aria-hidden="true">🧷</span>
        <span className="qa__label">Diaper</span>
      </button>
      <button
        type="button"
        className={`qa qa--sleep${isAsleep ? ' is-asleep' : ' is-awake'}`}
        onClick={onSleepClick}
        onPointerDown={startPress}
        onPointerUp={endPress}
        onPointerLeave={endPress}
        onPointerCancel={endPress}
        onContextMenu={(e) => e.preventDefault()}
        aria-label={isAsleep ? `${babyName} is sleeping. Tap when ${babyName} wakes.` : `${babyName} is awake. Tap when ${babyName} sleeps.`}
        title={isAsleep ? `Tap when ${babyName} wakes · long-press to back-fill` : `Tap when ${babyName} sleeps · long-press to back-fill`}
      >
        <span className="qa__icon" aria-hidden="true">{isAsleep ? '💤' : '☀️'}</span>
        <span className="qa__label">{isAsleep ? 'Sleeping' : 'Awake'}</span>
      </button>
      <button type="button" className="qa" onClick={onNote}>
        <span className="qa__icon" aria-hidden="true">📝</span>
        <span className="qa__label">Note</span>
      </button>
    </div>
  );
}
