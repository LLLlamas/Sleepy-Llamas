import { useState } from 'react';
import { Sheet } from '../ui/Sheet';
import { TimePicker } from '../ui/TimePicker';
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
import { fmtShortMin } from '../../lib/time';
import type { SleepSession } from '../../db/types';

const DAY = 24 * 60 * 60 * 1000;

interface Props {
  shiftId: string;
  onClose: () => void;
  editing?: SleepSession;
}

function resolveEnd(startMs: number, endMs: number): number {
  return endMs <= startMs ? endMs + DAY : endMs;
}

/**
 * Manual sleep entry / back-fill. Time-only (no calendar): pick asleep/woke
 * clock times and use the duration scroller for quick adjustment.
 */
export function SleepSheet({ shiftId, onClose, editing }: Props) {
  const { showToast } = useToast();
  const now = Date.now();

  const [startMs, setStartMs] = useState(() =>
    editing ? new Date(editing.startAt).getTime() : now - 30 * 60000,
  );
  const [stillAsleep, setStillAsleep] = useState(() => (editing ? !editing.endAt : false));
  const [endMs, setEndMs] = useState(() =>
    editing?.endAt ? new Date(editing.endAt).getTime() : now,
  );

  const resolvedEnd = stillAsleep ? undefined : resolveEnd(startMs, endMs);
  const durationMin =
    resolvedEnd !== undefined && !Number.isNaN(startMs) && !Number.isNaN(resolvedEnd)
      ? Math.max(0, Math.round((resolvedEnd - startMs) / 60000))
      : 0;
  const valid =
    !Number.isNaN(startMs) &&
    (stillAsleep || (resolvedEnd !== undefined && !Number.isNaN(resolvedEnd) && resolvedEnd > startMs));

  const changeStart = (nextStart: number) => {
    const existingDuration = durationMin;
    setStartMs(nextStart);
    if (!stillAsleep && existingDuration > 0) setEndMs(nextStart + existingDuration * 60000);
  };

  const changeEnd = (nextEnd: number) => {
    setStillAsleep(false);
    setEndMs(nextEnd);
  };

  const setDuration = (minutes: number) => {
    if (Number.isNaN(startMs)) return;
    if (minutes <= 0) {
      setStillAsleep(true);
      return;
    }
    setStillAsleep(false);
    setEndMs(startMs + minutes * 60000);
  };

  const save = async () => {
    const startAt = new Date(startMs).toISOString();
    const endAt = resolvedEnd !== undefined ? new Date(resolvedEnd).toISOString() : undefined;
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
        <span className="field-label">Asleep at</span>
        <TimePicker value={startMs} onChange={changeStart} ariaLabel="asleep time" referenceMs={now} />
      </div>

      <div className="sheet__field">
        <div className="field-label-row">
          <span className="field-label" style={{ marginBottom: 0 }}>Woke at</span>
          <button
            type="button"
            className={`mini-toggle${stillAsleep ? ' is-on' : ''}`}
            aria-pressed={stillAsleep}
            onClick={() => setStillAsleep((s) => !s)}
          >
            Still asleep
          </button>
        </div>
        {stillAsleep ? (
          <p className="field__hint">Open stretch - the timer keeps running until you log a wake time.</p>
        ) : (
          <>
            <TimePicker value={endMs} onChange={changeEnd} ariaLabel="woke time" referenceMs={now} />
            <p className="field__hint">
              {valid ? `Slept ${fmtShortMin(durationMin)}` : 'Wake time must be after the sleep time.'}
            </p>
          </>
        )}
      </div>

      <div className="sheet__field">
        <span className="field-label">Duration</span>
        <DurationScroller
          value={stillAsleep ? 0 : durationMin}
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
