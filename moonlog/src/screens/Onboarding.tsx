import { useState } from 'react';
import { format } from 'date-fns';
import { createBaby } from '../db/hooks';
import { buzz } from '../lib/haptics';

export function Onboarding() {
  const [name, setName] = useState('');
  const [birth, setBirth] = useState(() => format(new Date(), "yyyy-MM-dd'T'HH:mm"));

  const birthMs = new Date(birth).getTime();
  const valid = name.trim().length > 0 && !Number.isNaN(birthMs);

  const submit = async () => {
    if (!valid) return;
    await createBaby(name, new Date(birthMs).toISOString());
    buzz();
  };

  return (
    <div className="app">
      <div className="app__scroll" style={{ paddingTop: 'calc(env(safe-area-inset-top) + 32px)' }}>
        <div style={{ textAlign: 'center', marginBottom: 20 }}>
          <div style={{ fontSize: 44 }} aria-hidden="true">
            🌙
          </div>
          <h1 className="screen-title" style={{ textAlign: 'center' }}>
            Welcome to Moonlog
          </h1>
          <p className="screen-sub" style={{ textAlign: 'center' }}>
            Night logging for newborn care
          </p>
        </div>

        <p className="note-banner">
          Everything you log stays on this device — it's never sent anywhere. Add the baby
          to begin; you can change these later in Settings.
        </p>

        <div className="field">
          <label className="field-label" htmlFor="ob-name">
            Baby's name
          </label>
          <input
            id="ob-name"
            className="input"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Theo"
            autoFocus
          />
        </div>

        <div className="field">
          <label className="field-label" htmlFor="ob-birth">
            Date & time of birth
          </label>
          <input
            id="ob-birth"
            className="input"
            type="datetime-local"
            value={birth}
            max={format(new Date(), "yyyy-MM-dd'T'HH:mm")}
            onChange={(e) => setBirth(e.target.value)}
          />
          <p className="field__hint">Drives "Day N" and the baby's age.</p>
        </div>

        <button type="button" className="btn btn--primary btn--block" disabled={!valid} onClick={submit}>
          Start logging
        </button>
      </div>
    </div>
  );
}
