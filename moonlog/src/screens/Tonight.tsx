import { StatusTiles } from '../components/StatusTiles';
import { Timeline } from '../components/Timeline';
import type { LogEvent, SleepSession } from '../db/types';
import type { Unit } from '../lib/units';

interface Props {
  events: LogEvent[];
  sleepSessions: SleepSession[];
  openSleep?: SleepSession;
  now: number;
  unit: Unit;
  dueSoonHours: number;
  onToggleSleep: () => void;
  onAddSleep: () => void;
  onEditEvent: (ev: LogEvent) => void;
  onEditSleep: (s: SleepSession) => void;
}

export function Tonight({
  events,
  sleepSessions,
  openSleep,
  now,
  unit,
  dueSoonHours,
  onToggleSleep,
  onAddSleep,
  onEditEvent,
  onEditSleep,
}: Props) {
  return (
    <>
      <StatusTiles
        events={events}
        openSleep={openSleep}
        now={now}
        dueSoonHours={dueSoonHours}
        onToggleSleep={onToggleSleep}
      />
      <div className="section-head">
        <span className="section-label">Timeline</span>
        <button type="button" className="section-action" onClick={onAddSleep}>
          Add past sleep
        </button>
      </div>
      {(events.length > 0 || sleepSessions.length > 0) && (
        <p className="timeline-hint">Tap any entry to edit or delete it.</p>
      )}
      <Timeline
        events={events}
        sleepSessions={sleepSessions}
        now={now}
        unit={unit}
        onEditEvent={onEditEvent}
        onEditSleep={onEditSleep}
      />
    </>
  );
}
