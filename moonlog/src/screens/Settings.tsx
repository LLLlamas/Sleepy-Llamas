import { useEffect, useState } from 'react';
import { format } from 'date-fns';
import type { Baby, Shift } from '../db/types';
import type { FeedMethod } from '../db/types';
import { useSettings, type ThemeName } from '../state/SettingsContext';
import { useToast } from '../state/ToastContext';
import {
  updateBaby,
  updateShift,
  exportJSON,
  clearShiftData,
  clearAllData,
} from '../db/hooks';
import { Stepper } from '../components/ui/Stepper';
import { DeleteRow } from '../components/sheets/DeleteRow';
import { dayNumber } from '../lib/time';
import { METHOD_LABEL } from '../lib/labels';
import type { Unit } from '../lib/units';

interface SegOpt<T extends string> {
  value: T;
  label: string;
}
function Segmented<T extends string>({
  value,
  options,
  onChange,
  ariaLabel,
}: {
  value: T;
  options: SegOpt<T>[];
  onChange: (v: T) => void;
  ariaLabel: string;
}) {
  return (
    <div className="segmented" role="group" aria-label={ariaLabel}>
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          className={`segmented__opt${value === o.value ? ' is-active' : ''}`}
          aria-pressed={value === o.value}
          onClick={() => onChange(o.value)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

const THEMES: SegOpt<ThemeName>[] = [
  { value: 'night', label: 'Night' },
  { value: 'deep-night', label: 'Deep Night' },
  { value: 'day', label: 'Day' },
];
const UNITS: SegOpt<Unit>[] = [
  { value: 'oz', label: 'oz' },
  { value: 'ml', label: 'ml' },
];
const TEMPS: SegOpt<'F' | 'C'>[] = [
  { value: 'F', label: '°F' },
  { value: 'C', label: '°C' },
];
const METHODS: FeedMethod[] = ['breast-left', 'breast-right', 'bottle-breastmilk', 'bottle-formula'];

interface Props {
  baby: Baby;
  shift: Shift;
  now: number;
}

function isStandalone(): boolean {
  return (
    window.matchMedia?.('(display-mode: standalone)').matches ||
    // iOS Safari
    (navigator as unknown as { standalone?: boolean }).standalone === true
  );
}

export function Settings({ baby, shift, now }: Props) {
  const { settings, update } = useSettings();
  const { showToast } = useToast();

  const [name, setName] = useState(baby.name);
  const [birth, setBirth] = useState(format(new Date(baby.birthAt), "yyyy-MM-dd'T'HH:mm"));
  const [caregiver, setCaregiver] = useState(shift.caregiver ?? settings.caregiver);
  const [persisted, setPersisted] = useState<boolean | null>(null);
  const wakeSupported = typeof navigator !== 'undefined' && 'wakeLock' in navigator;

  useEffect(() => {
    navigator.storage?.persisted?.().then(setPersisted).catch(() => setPersisted(null));
  }, []);

  const saveName = () => {
    const n = name.trim();
    if (n && n !== baby.name) updateBaby(baby.id, { name: n });
  };
  const saveBirth = () => {
    const ms = new Date(birth).getTime();
    if (!Number.isNaN(ms)) updateBaby(baby.id, { birthAt: new Date(ms).toISOString() });
  };
  const saveCaregiver = () => {
    const c = caregiver.trim();
    updateShift(shift.id, { caregiver: c || undefined });
    update({ caregiver: c });
  };

  const requestPersist = async () => {
    const r = await navigator.storage?.persist?.();
    setPersisted(!!r);
    showToast(r ? 'Storage is now persistent' : 'Browser declined persistent storage');
  };

  const onExport = async () => {
    const json = await exportJSON();
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `moonlog-${format(new Date(now), 'yyyy-MM-dd-HHmm')}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    showToast('Exported JSON');
  };

  const showIosHint = !settings.iosHintDismissed && !isStandalone();

  return (
    <>
      <h1 className="screen-title">Settings</h1>
      <p className="screen-sub">Moonlog · {baby.name}, Day {dayNumber(baby.birthAt, now)}</p>

      {showIosHint && (
        <div className="ios-hint">
          <span>
            <strong>Install Moonlog:</strong> in Safari, tap Share → <em>Add to Home Screen</em>.
            It then opens full-screen and works offline.
          </span>
          <button type="button" onClick={() => update({ iosHintDismissed: true })} aria-label="Dismiss">
            Got it
          </button>
        </div>
      )}

      {/* Baby */}
      <div className="setting">
        <div className="setting__label">Baby's name</div>
        <input
          className="input"
          value={name}
          onChange={(e) => setName(e.target.value)}
          onBlur={saveName}
          maxLength={24}
        />
      </div>
      <div className="setting">
        <div className="setting__label">Date & time of birth</div>
        <input
          className="input"
          type="datetime-local"
          value={birth}
          max={format(new Date(now), "yyyy-MM-dd'T'HH:mm")}
          onChange={(e) => setBirth(e.target.value)}
          onBlur={saveBirth}
        />
      </div>
      <div className="setting">
        <div className="setting__label">Caregiver (this shift)</div>
        <div className="setting__hint">Added to the shift handoff summary.</div>
        <input
          className="input"
          value={caregiver}
          onChange={(e) => setCaregiver(e.target.value)}
          onBlur={saveCaregiver}
          placeholder="e.g. Lorenzo"
        />
      </div>

      {/* Display */}
      <div className="setting">
        <div className="setting__label">Theme</div>
        <Segmented ariaLabel="Theme" value={settings.theme} options={THEMES} onChange={(v) => update({ theme: v })} />
      </div>
      <div className="setting">
        <div className="setting__label">Amount units</div>
        <Segmented ariaLabel="Units" value={settings.unit} options={UNITS} onChange={(v) => update({ unit: v })} />
      </div>
      <div className="setting">
        <div className="setting__label">Temperature unit</div>
        <div className="setting__hint">Display only. Fever threshold: 100.4°F / 38°C.</div>
        <Segmented ariaLabel="Temperature unit" value={settings.tempUnit} options={TEMPS} onChange={(v) => update({ tempUnit: v })} />
      </div>
      <div className="setting">
        <div className="setting__label">Default feed method</div>
        <div className="setting__hint">Pre-selected when the feed sheet has no recent feed to copy.</div>
        <Segmented
          ariaLabel="Default feed method"
          value={settings.feedDefault}
          options={METHODS.map((m) => ({ value: m, label: METHOD_LABEL[m] }))}
          onChange={(v) => update({ feedDefault: v })}
        />
      </div>
      <div className="setting">
        <div className="setting__label">Due-soon threshold</div>
        <div className="setting__hint">The Last-feed tile warms past this many hours.</div>
        <Stepper
          ariaLabel="Due-soon threshold hours"
          onDec={() => update({ dueSoonHours: Math.max(1, settings.dueSoonHours - 1) })}
          onInc={() => update({ dueSoonHours: Math.min(8, settings.dueSoonHours + 1) })}
          decDisabled={settings.dueSoonHours <= 1}
          incDisabled={settings.dueSoonHours >= 8}
        >
          {settings.dueSoonHours}h
        </Stepper>
      </div>
      <div className="setting">
        <div className="setting__label">Keep screen awake</div>
        <div className="setting__hint">
          Stops the screen dimming while you log through a feed.
          {!wakeSupported && ' (Not supported on this device.)'}
        </div>
        <Segmented
          ariaLabel="Keep screen awake"
          value={settings.keepAwake ? 'on' : 'off'}
          options={[
            { value: 'on', label: 'On' },
            { value: 'off', label: 'Off' },
          ]}
          onChange={(v) => update({ keepAwake: v === 'on' })}
        />
      </div>

      {/* Data */}
      <div className="section-label" style={{ marginTop: 22 }}>
        Data
      </div>
      <div className="setting">
        <div className="storage-pill">
          <span className={`dot${persisted ? '' : ' is-off'}`} />
          Storage: {persisted === null ? 'unknown' : persisted ? 'persistent ✓' : 'best-effort ✗'}
        </div>
        {!persisted && (
          <div style={{ marginTop: 10 }}>
            <button type="button" className="btn btn--ghost btn--block" onClick={requestPersist}>
              Request persistent storage
            </button>
          </div>
        )}
      </div>
      <div className="setting">
        <button type="button" className="btn btn--ghost btn--block" onClick={onExport}>
          Export all data (JSON)
        </button>
      </div>
      <div className="setting">
        <DeleteRow
          label="Clear current shift's logs"
          onDelete={async () => {
            await clearShiftData(shift.id);
            showToast('Current shift cleared');
          }}
        />
      </div>
      <div className="setting" style={{ borderBottom: 'none' }}>
        <DeleteRow
          label="Clear ALL data"
          onDelete={async () => {
            await clearAllData();
            showToast('All data cleared');
          }}
        />
      </div>

      <p className="note-banner" style={{ marginTop: 18 }}>
        <strong>Private by design.</strong> All logs live only on this device and are never
        transmitted. Moonlog records what happened — it doesn't diagnose, advise, or alarm.
        The temperature flag is a visual cue only; always tell the parents and let them and
        their pediatrician decide.
      </p>
    </>
  );
}
