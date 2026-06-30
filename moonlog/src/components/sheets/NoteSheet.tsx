import { useState } from 'react';
import { Sheet } from '../ui/Sheet';
import { Chip } from '../ui/Chip';
import { TimeField } from './TimeField';
import { DeleteRow } from './DeleteRow';
import { useSettings } from '../../state/SettingsContext';
import { useToast } from '../../state/ToastContext';
import { addNote, updateEvent, deleteEvent, restoreEvent } from '../../db/hooks';
import { buzz } from '../../lib/haptics';
import { fmtClockShort } from '../../lib/time';
import { tagLabel } from '../../lib/labels';
import type { NoteEvent } from '../../db/types';

const QUICK_TAGS = ['spit-up', 'fussy', 'jaundice', 'pumped', 'temp'];

const FEVER_F = 100.4;
const cToF = (c: number) => (c * 9) / 5 + 32;
const fToC = (f: number) => ((f - 32) * 5) / 9;

interface Props {
  shiftId: string;
  onClose: () => void;
  editing?: NoteEvent;
}

export function NoteSheet({ shiftId, onClose, editing }: Props) {
  const { settings } = useSettings();
  const { showToast } = useToast();

  const [time, setTime] = useState(() => (editing ? new Date(editing.at).getTime() : Date.now()));
  const [text, setText] = useState(editing?.text ?? '');
  const [tags, setTags] = useState<string[]>(editing?.tags ?? []);
  const [custom, setCustom] = useState('');
  const [tempStr, setTempStr] = useState(() => {
    if (editing?.tempF == null) return '';
    const v = settings.tempUnit === 'C' ? fToC(editing.tempF) : editing.tempF;
    return String(Math.round(v * 10) / 10);
  });

  const showTemp = tags.includes('temp');
  const tempNum = tempStr.trim() ? Number(tempStr) : NaN;
  const tempF = !Number.isNaN(tempNum)
    ? settings.tempUnit === 'C'
      ? cToF(tempNum)
      : tempNum
    : undefined;
  const feverFlag = tempF != null && tempF >= FEVER_F;

  const toggleTag = (t: string) =>
    setTags((cur) => (cur.includes(t) ? cur.filter((x) => x !== t) : [...cur, t]));

  const addCustom = () => {
    const v = custom.trim().toLowerCase();
    if (v && !tags.includes(v)) setTags((cur) => [...cur, v]);
    setCustom('');
  };

  const customTags = tags.filter((t) => !QUICK_TAGS.includes(t));
  const canSave = !!text.trim() || tags.some((t) => t !== 'temp') || tempF != null;

  const save = async () => {
    const at = new Date(time).toISOString();
    const finalTags = tags.filter((t) => t !== 'temp' || tempF != null);
    const data = {
      at,
      text: text.trim() || undefined,
      tags: finalTags.length ? finalTags : undefined,
      tempF: tempF != null ? Math.round(tempF * 10) / 10 : undefined,
    };
    if (editing) {
      await updateEvent(editing.id, data);
      showToast('Note updated');
    } else {
      const ev = await addNote(shiftId, data);
      showToast(`Note logged · ${fmtClockShort(ev.at)}`, {
        undo: () => deleteEvent(ev.id),
        durationMs: 1800,
      });
    }
    buzz();
    onClose();
  };

  return (
    <Sheet
      title={editing ? 'Edit note' : 'Note'}
      onClose={onClose}
      onSave={save}
      saveLabel={editing ? 'Save edits' : 'Save note'}
      saveDisabled={!canSave}
    >
      <TimeField value={time} onChange={setTime} />

      <div className="sheet__field">
        <label htmlFor="note-text">Note</label>
        <textarea
          id="note-text"
          className="textarea"
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="What happened?"
        />
      </div>

      <div className="sheet__field">
        <span className="field-label">Quick tags</span>
        <div className="chips">
          {QUICK_TAGS.map((t) => (
            <Chip key={t} selected={tags.includes(t)} onClick={() => toggleTag(t)}>
              {tagLabel(t)}
            </Chip>
          ))}
          {customTags.map((t) => (
            <Chip key={t} selected onClick={() => toggleTag(t)}>
              {tagLabel(t)} ✕
            </Chip>
          ))}
        </div>
        <div className="sheet__row" style={{ marginTop: 10 }}>
          <input
            className="input"
            value={custom}
            onChange={(e) => setCustom(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                addCustom();
              }
            }}
            placeholder="+ custom tag"
            aria-label="custom tag"
          />
          <button type="button" className="btn btn--ghost" style={{ flex: '0 0 auto', minWidth: 64 }} onClick={addCustom}>
            Add
          </button>
        </div>
      </div>

      {showTemp && (
        <div className="sheet__field">
          <label htmlFor="note-temp">Temperature (°{settings.tempUnit})</label>
          <input
            id="note-temp"
            className="input"
            type="number"
            inputMode="decimal"
            step="0.1"
            value={tempStr}
            onChange={(e) => setTempStr(e.target.value)}
            placeholder={settings.tempUnit === 'C' ? 'e.g. 37.0' : 'e.g. 99.1'}
          />
          {feverFlag && (
            <div className="temp-flag" role="note">
              Reads at or above the fever threshold (100.4°F / 38°C). This is a visual
              note only — see the field guide's escalation steps and tell the parents.
            </div>
          )}
        </div>
      )}

      {editing && (
        <DeleteRow
          label="Delete note"
          onDelete={async () => {
            await deleteEvent(editing.id);
            showToast('Note deleted', { undo: () => restoreEvent(editing) });
            buzz();
            onClose();
          }}
        />
      )}
    </Sheet>
  );
}
