import { useState } from 'react';
import { format } from 'date-fns';
import { Sheet } from '../ui/Sheet';
import { DurationScroller } from '../ui/DurationScroller';
import { DeleteRow } from './DeleteRow';
import { useToast } from '../../state/ToastContext';
import {
  addManualSleep,
  updateSleep,
  deleteSleep,
  restoreSleep,
} from '../../db/hooks';
import { buzz } from '../../lib/haptics';
import type { SleepSession } from '../../db/types';

const DAY = 24 * 60 * 60 * 1000;
const toClockInput = (ms: number) => format(new Date(ms), 'HH:mm');

function parseClockOnDate(clock: string, anchorMs: number): number | undefined {
  if (!clock) return undefined;
  const [h, m] = clock.split(':').map(Number);
  if (Number.isNaN(h) || Number.isNaN(m)) return undefined;
  const d = new Date(anchorMs);
  d.setHours(h, m, 0, 0);
  return d.getTime();
}

function inferStartMs(clock: string, currentMs: number): number | undefined {
  const ms = parseClockOnDate(clock, currentMs);
  if (ms === undefined) return undefined;
  return ms - Date.now() > 12 * 60 * 60 * 1000 ? ms - DAY : ms;
}

function inferEndMs(clock: string, startMs: number): number | undefined {
  let ms = parseClockOnDate(clock, startMs);
  if (ms === undefined) return undefined;
  if (ms <= startMs) ms += DAY;
  return ms;
}

interface Props {
  shiftId: string;
  onClose: () => void;
  editing?: SleepSession;
}

/** Manual sleep entry / back-fill (spec: long-press → manual session). */
export function SleepSheet({ shiftId, onClose, editing }: Props) {
  const { showToast } = useToast();
  const [startMs, setStartMs] = useState(() =>
    editing ? new Date(editing.startAt).getTime() : Date.now() - 30 * 60000,
  );
  const [endMs, setEndMs] = useState<number | undefined>(() =>
    editing?.endAt ? new Date(editing.endAt).getTime() : undefined,
  );

  const durationMin =
    endMs !== undefined && !Number.isNaN(startMs) && !Number.isNaN(endMs) && endMs > startMs
      ? Math.round((endMs - startMs) / 60000)
      : 0;
  const valid =
    !Number.isNaN(startMs) && (endMs === undefined || (!Number.isNaN(endMs) && endMs > startMs));

  const setDuration = (minutes: number) => {
    if (Number.isNaN(startMs)) return;
    setEndMs(minutes > 0 ? startMs + minutes * 60000 : undefined);
  };

  const changeStart = (clock: string) => {
    const nextStart = inferStartMs(clock, startMs);
    if (nextStart === undefined) return;
    const existingDuration = durationMin;
    setStartMs(nextStart);
    if (existingDuration > 0) setEndMs(nextStart + existingDuration * 60000);
  };

  const changeEnd = (clock: string) => {
    setEndMs(inferEndMs(clock, startMs));
  };

  const save = async () => {
    const startAt = new Date(startMs).toISOString();
    const endAt = endMs !== undefined ? new Date(endMs).toISOString() : undefined;
    if (editing) {
      await updateSleep(editing.id, { startAt, endAt });
      showToast('Sleep updated');
    } else {
      await addManualSleep(shiftId, startAt, endAt);
      showToast('Sleep added');
    }
    buzz();
    onClose();
  };

  return (
    <Sheet
      title={editing ? 'Edit sleep' : 'Add sleep'}
      onClose={onClose}
      onSave={save}
      saveLabel={editing ? 'Save edits' : 'Save'}
      saveDisabled={!valid}
    >
      <div className="sheet__field">
        <label htmlFor="sleep-start">Asleep at</label>
        <div className="time-row">
          <input
            id="sleep-start"
            className="input time-input tabular"
            type="time"
            value={toClockInput(startMs)}
            onChange={(e) => changeStart(e.target.value)}
          />
          <button type="button" className="time-now" onClick={() => setStartMs(Date.now())}>
            Now
          </button>
        </div>
      </div>

      <div className="sheet__field">
        <label htmlFor="sleep-end">Woke at (leave empty if still asleep)</label>
        <input
          id="sleep-end"
          className="input time-input tabular"
          type="time"
          value={endMs ? toClockInput(endMs) : ''}
          onChange={(e) => changeEnd(e.target.value)}
        />
        {!valid && endMs !== undefined && <p className="field__hint">Wake time must be after the sleep time.</p>}
      </div>

      <div className="sheet__field">
        <span className="field-label">Duration</span>
        <DurationScroller
          value={durationMin}
          onChange={setDuration}
          maxHours={12}
          minuteStep={5}
          zeroLabel="Still asleep"
          ariaLabel="Sleep duration"
        />
        <p className="field__hint">Scroll hours and minutes to adjust the wake time.</p>
      </div>

      {editing && (
        <DeleteRow
          label="Delete sleep"
          onDelete={async () => {
            await deleteSleep(editing.id);
            showToast('Sleep deleted', { undo: () => restoreSleep(editing) });
            buzz();
            onClose();
          }}
        />
      )}
    </Sheet>
  );
}
