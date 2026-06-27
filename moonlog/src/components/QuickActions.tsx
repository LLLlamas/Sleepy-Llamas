import { useRef } from 'react';

interface Props {
  isAsleep: boolean;
  onFeed: () => void;
  onDiaper: () => void;
  onSleepToggle: () => void;
  onSleepManual: () => void;
  onNote: () => void;
}

const LONG_PRESS_MS = 500;

export function QuickActions({
  isAsleep,
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
        className={`qa qa--sleep${isAsleep ? ' is-asleep' : ''}`}
        onClick={onSleepClick}
        onPointerDown={startPress}
        onPointerUp={endPress}
        onPointerLeave={endPress}
        onPointerCancel={endPress}
        onContextMenu={(e) => e.preventDefault()}
        title="Tap to toggle · long-press to back-fill"
      >
        <span className="qa__icon" aria-hidden="true">{isAsleep ? '😴' : '🌙'}</span>
        <span className="qa__label">{isAsleep ? 'Woke up' : 'Sleep'}</span>
      </button>
      <button type="button" className="qa" onClick={onNote}>
        <span className="qa__icon" aria-hidden="true">📝</span>
        <span className="qa__label">Note</span>
      </button>
    </div>
  );
}
