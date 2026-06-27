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
      <div className="section-label">Timeline</div>
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
