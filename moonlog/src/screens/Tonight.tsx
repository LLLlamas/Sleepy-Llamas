import { StatusTiles } from '../components/StatusTiles';
import { Timeline } from '../components/Timeline';
import type { LogEvent, SleepSession } from '../db/types';
import type { Unit } from '../lib/units';

interface Props {
  events: LogEvent[];
  sleepSessions: SleepSession[];
  openSleep?: SleepSession;
  now: number;
  babyName: string;
  unit: Unit;
  dueSoonHours: number;
  onToggleSleep: () => void;
  onEditEvent: (ev: LogEvent) => void;
  onEditSleep: (s: SleepSession) => void;
}

export function Tonight({
  events,
  sleepSessions,
  openSleep,
  now,
  babyName,
  unit,
  dueSoonHours,
  onToggleSleep,
  onEditEvent,
  onEditSleep,
}: Props) {
  return (
    <>
      <StatusTiles
        events={events}
        openSleep={openSleep}
        now={now}
        babyName={babyName}
        dueSoonHours={dueSoonHours}
        onToggleSleep={onToggleSleep}
      />
      <div className="section-head">
        <span className="section-label">Timeline</span>
      </div>
      {(events.length > 0 || sleepSessions.length > 0) && (
        <p className="timeline-hint">Tap any entry to edit or delete it.</p>
      )}
      <Timeline
        events={events}
        sleepSessions={sleepSessions}
        now={now}
        babyName={babyName}
        unit={unit}
        onEditEvent={onEditEvent}
        onEditSleep={onEditSleep}
      />
    </>
  );
}
