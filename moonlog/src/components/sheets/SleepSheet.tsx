import { useState } from 'react';
import { format } from 'date-fns';
import { Sheet } from '../ui/Sheet';
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

const toLocalInput = (ms: number) => format(new Date(ms), "yyyy-MM-dd'T'HH:mm");

interface Props {
  shiftId: string;
  onClose: () => void;
  editing?: SleepSession;
}

/** Manual sleep entry / back-fill (spec: long-press → manual session). */
export function SleepSheet({ shiftId, onClose, editing }: Props) {
  const { showToast } = useToast();
  const [startStr, setStartStr] = useState(() =>
    toLocalInput(editing ? new Date(editing.startAt).getTime() : Date.now() - 30 * 60000),
  );
  const [endStr, setEndStr] = useState(() =>
    editing?.endAt ? toLocalInput(new Date(editing.endAt).getTime()) : '',
  );

  const startMs = new Date(startStr).getTime();
  const endMs = endStr ? new Date(endStr).getTime() : undefined;
  const valid =
    !Number.isNaN(startMs) && (endMs === undefined || (!Number.isNaN(endMs) && endMs > startMs));

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
      saveLabel={editing ? 'Update' : 'Save'}
      saveDisabled={!valid}
    >
      <div className="sheet__field">
        <label htmlFor="sleep-start">Asleep at</label>
        <input
          id="sleep-start"
          className="input"
          type="datetime-local"
          value={startStr}
          onChange={(e) => setStartStr(e.target.value)}
        />
      </div>

      <div className="sheet__field">
        <label htmlFor="sleep-end">Woke at (leave empty if still asleep)</label>
        <input
          id="sleep-end"
          className="input"
          type="datetime-local"
          value={endStr}
          min={startStr}
          onChange={(e) => setEndStr(e.target.value)}
        />
        {!valid && endStr && <p className="field__hint">Wake time must be after the sleep time.</p>}
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
