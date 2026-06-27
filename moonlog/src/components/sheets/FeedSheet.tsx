import { useState } from 'react';
import { Sheet } from '../ui/Sheet';
import { Chip } from '../ui/Chip';
import { Stepper } from '../ui/Stepper';
import { TimeField } from './TimeField';
import { DeleteRow } from './DeleteRow';
import { useSettings } from '../../state/SettingsContext';
import { useToast } from '../../state/ToastContext';
import { addFeed, updateEvent, deleteEvent, restoreEvent } from '../../db/hooks';
import { buzz } from '../../lib/haptics';
import { fmtClockShort, fmtShortMin } from '../../lib/time';
import { STEP, displayAmount, toMl, type Unit } from '../../lib/units';
import { METHOD_LABEL, isBottle } from '../../lib/labels';
import type { FeedEvent, FeedMethod } from '../../db/types';

const METHODS: FeedMethod[] = ['breast-left', 'breast-right', 'bottle-breastmilk', 'bottle-formula'];

const defaultAmount = (unit: Unit) => (unit === 'oz' ? 2 : 60);

function amountText(value: number, unit: Unit): string {
  const n = value % 1 === 0 ? String(value) : value.toFixed(1);
  return `${n} ${unit}`;
}

interface Props {
  shiftId: string;
  onClose: () => void;
  editing?: FeedEvent;
  lastMethod?: FeedMethod;
}

export function FeedSheet({ shiftId, onClose, editing, lastMethod }: Props) {
  const { settings } = useSettings();
  const { unit } = settings;
  const { showToast } = useToast();

  const [time, setTime] = useState(() =>
    editing ? new Date(editing.at).getTime() : Date.now(),
  );
  const [method, setMethod] = useState<FeedMethod>(
    editing?.method ?? lastMethod ?? settings.feedDefault,
  );
  const [amount, setAmount] = useState(() =>
    editing?.amountMl != null ? displayAmount(editing.amountMl, unit) : defaultAmount(unit),
  );
  const [duration, setDuration] = useState(editing?.durationMin ?? 0);
  const [note, setNote] = useState(editing?.note ?? '');

  const step = STEP[unit];

  const save = async () => {
    const at = new Date(time).toISOString();
    const amountMl = isBottle(method) && amount > 0 ? toMl(amount, unit) : undefined;
    const durationMin = duration > 0 ? duration : undefined;
    const trimmed = note.trim() || undefined;
    if (editing) {
      await updateEvent(editing.id, { at, method, amountMl, durationMin, note: trimmed });
      showToast('Feed updated');
    } else {
      const ev = await addFeed(shiftId, { at, method, amountMl, durationMin, note: trimmed });
      showToast(`Feed logged · ${fmtClockShort(ev.at)}`, { undo: () => deleteEvent(ev.id) });
    }
    buzz();
    onClose();
  };

  return (
    <Sheet
      title={editing ? 'Edit feed' : 'Feed'}
      onClose={onClose}
      onSave={save}
      saveLabel={editing ? 'Update' : 'Save feed'}
    >
      <TimeField value={time} onChange={setTime} />

      <div className="sheet__field">
        <span className="field-label">Method</span>
        <div className="chips">
          {METHODS.map((m) => (
            <Chip key={m} selected={method === m} onClick={() => setMethod(m)}>
              {METHOD_LABEL[m]}
            </Chip>
          ))}
        </div>
      </div>

      {isBottle(method) && (
        <div className="sheet__field">
          <span className="field-label">Amount</span>
          <Stepper
            ariaLabel="amount"
            onDec={() => setAmount((a) => Math.max(0, Math.round((a - step) * 100) / 100))}
            onInc={() => setAmount((a) => Math.round((a + step) * 100) / 100)}
            decDisabled={amount <= 0}
          >
            {amount > 0 ? amountText(amount, unit) : '—'}
          </Stepper>
        </div>
      )}

      <div className="sheet__field">
        <span className="field-label">Duration (optional)</span>
        <Stepper
          ariaLabel="duration"
          decLabel="−5"
          incLabel="+5"
          onDec={() => setDuration((d) => Math.max(0, d - 5))}
          onInc={() => setDuration((d) => d + 5)}
          decDisabled={duration <= 0}
        >
          {duration > 0 ? fmtShortMin(duration) : '—'}
        </Stepper>
      </div>

      <div className="sheet__field">
        <label htmlFor="feed-note">Note (optional)</label>
        <input
          id="feed-note"
          className="input"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="e.g. burped well"
        />
      </div>

      {editing && (
        <DeleteRow
          label="Delete feed"
          onDelete={async () => {
            await deleteEvent(editing.id);
            showToast('Feed deleted', { undo: () => restoreEvent(editing) });
            buzz();
            onClose();
          }}
        />
      )}
    </Sheet>
  );
}
