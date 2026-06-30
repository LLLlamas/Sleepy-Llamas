import { useState } from 'react';
import { Sheet } from '../ui/Sheet';
import { TimePicker } from '../ui/TimePicker';
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

interface Props {
  shiftId: string;
  onClose: () => void;
  editing?: SleepSession;
}

/**
 * Manual sleep entry / back-fill. Time-only (no calendar): pick the asleep and
 * woke clock times and we work out the dates — if "woke" reads earlier than
 * "asleep" it's treated as the next morning, so an 11:40pm → 12:25am stretch
 * just works.
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

  // If the woke clock-time lands before the asleep instant, roll it to the next
  // day so an overnight stretch reads correctly.
  const resolvedEnd = (() => {
    if (stillAsleep) return undefined;
    let e = endMs;
    if (e <= startMs) e += 24 * 60 * 60 * 1000;
    return e;
  })();

  const valid = stillAsleep || (resolvedEnd !== undefined && resolvedEnd > startMs);
  const durationMin = resolvedEnd !== undefined ? Math.round((resolvedEnd - startMs) / 60000) : 0;

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
      saveLabel={editing ? 'Update' : 'Save'}
      saveDisabled={!valid}
    >
      <div className="sheet__field">
        <span className="field-label">Asleep at</span>
        <TimePicker value={startMs} onChange={setStartMs} ariaLabel="asleep time" referenceMs={now} />
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
          <p className="field__hint">Open stretch — the timer keeps running until you log a wake time.</p>
        ) : (
          <>
            <TimePicker value={endMs} onChange={setEndMs} ariaLabel="woke time" referenceMs={now} />
            <p className="field__hint">
              {valid ? `Slept ${fmtShortMin(durationMin)}` : 'Wake time must be after the sleep time.'}
            </p>
          </>
        )}
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
