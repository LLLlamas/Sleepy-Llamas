import type { LogEvent, SleepSession } from '../db/types';
import type { Unit } from '../lib/units';
import { eventIcon, eventSummary } from '../lib/labels';
import { fmtClockShort, fmtShortMin, spanMinutes, sinceISO } from '../lib/time';

interface Props {
  events: LogEvent[];
  sleepSessions: SleepSession[];
  now: number;
  unit: Unit;
  onEditEvent: (ev: LogEvent) => void;
  onEditSleep: (s: SleepSession) => void;
}

type Item =
  | { kind: 'event'; t: number; ev: LogEvent }
  | { kind: 'sleep'; t: number; s: SleepSession };

export function Timeline({ events, sleepSessions, now, unit, onEditEvent, onEditSleep }: Props) {
  const items: Item[] = [
    ...events.map((ev) => ({ kind: 'event' as const, t: new Date(ev.at).getTime(), ev })),
    ...sleepSessions.map((s) => ({ kind: 'sleep' as const, t: new Date(s.startAt).getTime(), s })),
  ].sort((a, b) => b.t - a.t);

  if (items.length === 0) {
    return (
      <div className="empty">
        <span className="moon" aria-hidden="true">
          🌙
        </span>
        Quiet start. Log the first feed, diaper, sleep, or note below.
      </div>
    );
  }

  const ago = (iso: string) => {
    const s = sinceISO(iso, now);
    return s === 'just now' ? s : `${s} ago`;
  };

  return (
    <ul className="timeline">
      {items.map((item) =>
        item.kind === 'event' ? (
          <li key={item.ev.id}>
            <button type="button" className="row" onClick={() => onEditEvent(item.ev)}>
              <span className="row__icon" aria-hidden="true">
                {eventIcon(item.ev.type)}
              </span>
              <span className="row__main">
                <span className="row__title">{eventSummary(item.ev, unit)}</span>
                <span className="row__meta tabular">
                  {fmtClockShort(item.ev.at)} · {ago(item.ev.at)}
                </span>
              </span>
              <span className="row__chev" aria-hidden="true">›</span>
            </button>
          </li>
        ) : (
          <li key={item.s.id}>
            <button
              type="button"
              className={`row row--sleep${item.s.endAt ? '' : ' is-open'}`}
              onClick={() => onEditSleep(item.s)}
            >
              <span className="row__icon" aria-hidden="true">
                😴
              </span>
              <span className="row__main">
                <span className="row__title">
                  {item.s.endAt ? 'Sleep' : 'Currently asleep'}
                </span>
                <span className="row__meta tabular">
                  {item.s.endAt
                    ? `${fmtClockShort(item.s.startAt)} → ${fmtClockShort(item.s.endAt)} · ${fmtShortMin(spanMinutes(item.s.startAt, item.s.endAt))}`
                    : `Started ${fmtClockShort(item.s.startAt)} · ${fmtShortMin(spanMinutes(item.s.startAt, now))}`}
                </span>
              </span>
              <span className="row__chev" aria-hidden="true">›</span>
            </button>
          </li>
        ),
      )}
    </ul>
  );
}
