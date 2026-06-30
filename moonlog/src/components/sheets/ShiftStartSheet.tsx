import { useState } from 'react';
import { Sheet } from '../ui/Sheet';
import { TimePicker } from '../ui/TimePicker';
import { useToast } from '../../state/ToastContext';
import { updateShift } from '../../db/hooks';
import { buzz } from '../../lib/haptics';
import type { Shift } from '../../db/types';

interface Props {
  shift: Shift;
  onClose: () => void;
}

/** Adjust when tonight's shift began — drives the handoff start time. */
export function ShiftStartSheet({ shift, onClose }: Props) {
  const { showToast } = useToast();
  const now = Date.now();
  const [startMs, setStartMs] = useState(() => new Date(shift.startedAt).getTime());

  const future = startMs > now + 60000;

  const save = async () => {
    await updateShift(shift.id, { startedAt: new Date(startMs).toISOString() });
    showToast('Shift start updated');
    buzz();
    onClose();
  };

  return (
    <Sheet title="Shift start" onClose={onClose} onSave={save} saveLabel="Save" saveDisabled={future}>
      <p className="sheet__note">When did tonight's shift begin? This sets the start time on the handoff.</p>
      <div className="sheet__field">
        <span className="field-label">Shift started</span>
        <TimePicker value={startMs} onChange={setStartMs} ariaLabel="shift start time" referenceMs={now} />
        {future && <p className="field__hint">That's in the future — pick a time at or before now.</p>}
      </div>
    </Sheet>
  );
}
