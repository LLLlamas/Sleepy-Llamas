import { useState } from 'react';
import { Sheet } from '../ui/Sheet';
import { Chip } from '../ui/Chip';
import { Swatch } from '../ui/Swatch';
import { TimeField } from './TimeField';
import { DeleteRow } from './DeleteRow';
import { useToast } from '../../state/ToastContext';
import { addDiaper, updateEvent, deleteEvent, restoreEvent } from '../../db/hooks';
import { buzz } from '../../lib/haptics';
import { fmtClockShort } from '../../lib/time';
import { CONTENTS_LABEL, STOOL_LABEL, STOOL_ORDER, STOOL_SWATCH } from '../../lib/labels';
import type { DiaperContents, DiaperEvent, StoolColor } from '../../db/types';

const CONTENTS: DiaperContents[] = ['wet', 'dirty', 'both'];

interface Props {
  shiftId: string;
  onClose: () => void;
  editing?: DiaperEvent;
}

export function DiaperSheet({ shiftId, onClose, editing }: Props) {
  const { showToast } = useToast();
  const [time, setTime] = useState(() => (editing ? new Date(editing.at).getTime() : Date.now()));
  const [contents, setContents] = useState<DiaperContents>(editing?.contents ?? 'wet');
  const [stool, setStool] = useState<StoolColor | undefined>(editing?.stool);
  const [note, setNote] = useState(editing?.note ?? '');

  const showStool = contents === 'dirty' || contents === 'both';

  const save = async () => {
    const at = new Date(time).toISOString();
    const stoolVal = showStool ? stool : undefined;
    const trimmed = note.trim() || undefined;
    if (editing) {
      await updateEvent(editing.id, { at, contents, stool: stoolVal, note: trimmed });
      showToast('Diaper updated');
    } else {
      const ev = await addDiaper(shiftId, { at, contents, stool: stoolVal, note: trimmed });
      showToast(`Diaper logged · ${fmtClockShort(ev.at)}`, {
        undo: () => deleteEvent(ev.id),
        durationMs: 1000,
      });
    }
    buzz();
    onClose();
  };

  return (
    <Sheet
      title={editing ? 'Edit diaper' : 'Diaper'}
      onClose={onClose}
      onSave={save}
      saveLabel={editing ? 'Save edits' : 'Save diaper'}
    >
      <TimeField value={time} onChange={setTime} />

      <div className="sheet__field">
        <span className="field-label">Contents</span>
        <div className="chips">
          {CONTENTS.map((c) => (
            <Chip key={c} selected={contents === c} onClick={() => setContents(c)}>
              {CONTENTS_LABEL[c]}
            </Chip>
          ))}
        </div>
      </div>

      {showStool && (
        <div className="sheet__field">
          <span className="field-label">Stool color</span>
          <div className="swatches">
            {STOOL_ORDER.map((s) => (
              <Swatch
                key={s}
                color={STOOL_SWATCH[s]}
                name={STOOL_LABEL[s]}
                selected={stool === s}
                onClick={() => setStool((cur) => (cur === s ? undefined : s))}
              />
            ))}
          </div>
        </div>
      )}

      <div className="sheet__field">
        <label htmlFor="diaper-note">Note (optional)</label>
        <input
          id="diaper-note"
          className="input"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="e.g. small leak"
        />
      </div>

      {editing && (
        <DeleteRow
          label="Delete diaper"
          onDelete={async () => {
            await deleteEvent(editing.id);
            showToast('Diaper deleted', { undo: () => restoreEvent(editing) });
            buzz();
            onClose();
          }}
        />
      )}
    </Sheet>
  );
}
