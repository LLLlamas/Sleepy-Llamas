import { useEffect, useState } from 'react';
import type { Baby, LogEvent, Shift, SleepSession } from '../db/types';
import type { Unit } from '../lib/units';
import { computeTotals, buildSummaryText } from '../lib/summary';
import { useRecentShifts } from '../db/hooks';
import { useToast } from '../state/ToastContext';
import { ConfirmDialog } from '../components/ui/ConfirmDialog';
import {
  dayNumber,
  fmtClockLong,
  fmtClockShort,
  fmtShortMin,
  sinceISO,
} from '../lib/time';
import { formatAmount } from '../lib/units';
import { STOOL_LABEL } from '../lib/labels';
import { format } from 'date-fns';

interface Props {
  baby: Baby;
  shift: Shift;
  events: LogEvent[];
  sleepSessions: SleepSession[];
  now: number;
  unit: Unit;
  onEndShift: () => void;
}

async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    try {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      return true;
    } catch {
      return false;
    }
  }
}

export function Summary({ baby, shift, events, sleepSessions, now, unit, onEndShift }: Props) {
  const { showToast } = useToast();
  const recent = useRecentShifts(baby.id);
  const totals = computeTotals(events, sleepSessions, now);
  const generated = buildSummaryText(baby, shift, events, sleepSessions, unit, now);
  const [shareSupported] = useState(() => typeof navigator !== 'undefined' && 'share' in navigator);

  // Editable handoff: `draft` holds the user's edits (persisted per shift so a
  // tab switch / reload doesn't lose them). null = use the live auto-generated text.
  const draftKey = `moonlog.handoff.${shift.id}`;
  const [draft, setDraft] = useState<string | null>(() => {
    try {
      return localStorage.getItem(draftKey);
    } catch {
      return null;
    }
  });
  useEffect(() => {
    try {
      setDraft(localStorage.getItem(draftKey));
    } catch {
      setDraft(null);
    }
  }, [draftKey]);

  const text = draft ?? generated;
  const edited = draft !== null;
  const editDraft = (v: string) => {
    setDraft(v);
    try {
      localStorage.setItem(draftKey, v);
    } catch {
      /* ignore */
    }
  };
  const resetDraft = () => {
    setDraft(null);
    try {
      localStorage.removeItem(draftKey);
    } catch {
      /* ignore */
    }
    showToast('Reset to the live handoff');
  };

  const [confirmEnd, setConfirmEnd] = useState(false);

  const onCopy = async () => {
    const ok = await copyText(text);
    showToast(ok ? 'Summary copied' : 'Copy failed — select & copy manually');
  };
  const onShare = async () => {
    if (shareSupported) {
      try {
        await navigator.share({ text });
        return;
      } catch {
        /* user cancelled or failed — fall through to copy */
      }
    }
    onCopy();
  };

  const stoolProgression = totals.stoolProgression.map((s) => STOOL_LABEL[s]).join(' → ');
  const endText = shift.endedAt ?? now;
  const isEmpty = events.length === 0 && sleepSessions.length === 0;
  const currentDate = format(new Date(now), 'EEE, MMM d');
  const currentTime = fmtClockLong(now);
  const shiftStarted = fmtClockLong(shift.startedAt);

  const archived = (recent ?? []).filter((s) => s.endedAt && s.id !== shift.id);

  return (
    <>
      <div className="summary-hero">
        <div>
          <h1 className="screen-title">Shift summary</h1>
          <p className="summary-hero__date tabular">
            {currentDate} · {currentTime}
          </p>
        </div>
        <span className="summary-hero__badge">EDIT</span>
      </div>
      <p className="screen-sub summary-start">
        Shift started at {shiftStarted} · {baby.name}, Day {dayNumber(baby.birthAt, now)} ·{' '}
        through {shift.endedAt ? fmtClockShort(shift.endedAt) : fmtClockShort(endText)}
      </p>

      {isEmpty && (
        <p className="note-banner">Nothing logged this shift yet — the summary fills in as you log.</p>
      )}

      <div className="stat-card">
        <div className="stat">
          <span className="stat__label">Feeds</span>
          <span className="stat__value tabular">
            {totals.feeds}
            {totals.feedMl ? <span className="stat__detail"> · {formatAmount(totals.feedMl, unit)}</span> : null}
          </span>
        </div>
        <div className="stat">
          <span className="stat__label">Diapers</span>
          <span className="stat__value tabular">
            {totals.diapers}
            <span className="stat__detail">
              {' '}· {totals.wet} wet · {totals.dirty} dirty
            </span>
          </span>
        </div>
        {stoolProgression && (
          <div className="stat">
            <span className="stat__label">Stool</span>
            <span className="stat__detail">{stoolProgression}</span>
          </div>
        )}
        <div className="stat">
          <span className="stat__label">Sleep</span>
          <span className="stat__value tabular">
            {fmtShortMin(totals.sleepMin)}
            <span className="stat__detail">
              {' '}· {totals.stretches} stretch{totals.stretches === 1 ? '' : 'es'}
              {totals.longestMin ? ` · longest ${fmtShortMin(totals.longestMin)}` : ''}
            </span>
          </span>
        </div>
        <div className="stat">
          <span className="stat__label">Notes</span>
          <span className="stat__value tabular">{totals.notes}</span>
        </div>
      </div>

      <div className="btn-row">
        <button type="button" className="btn btn--primary" onClick={onCopy}>
          Copy summary
        </button>
        <button type="button" className="btn btn--ghost" onClick={onShare}>
          {shareSupported ? 'Share' : 'Copy as text'}
        </button>
      </div>

      <div className="section-head">
        <span className="section-label">Handoff — edit before sending</span>
        {edited && (
          <button type="button" className="section-action" onClick={resetDraft}>
            Reset
          </button>
        )}
      </div>
      <textarea
        className="handoff-edit"
        value={text}
        onChange={(e) => editDraft(e.target.value)}
        aria-label="Handoff summary (editable)"
        spellCheck={false}
      />

      <div className="section-label">End of shift</div>
      <p className="screen-sub" style={{ marginBottom: 10 }}>
        Archives this shift and starts a fresh one.
      </p>
      <button
        type="button"
        className="btn btn--danger btn--block"
        onClick={() => setConfirmEnd(true)}
      >
        End shift &amp; start fresh
      </button>

      {confirmEnd && (
        <ConfirmDialog
          title="End shift & start fresh?"
          message={`This archives ${baby.name}'s current shift and starts a new, empty one. Copy or share the handoff first — it won't be shown here again.`}
          confirmLabel="End shift"
          danger
          onCancel={() => setConfirmEnd(false)}
          onConfirm={() => {
            setConfirmEnd(false);
            try {
              localStorage.removeItem(draftKey);
            } catch {
              /* ignore */
            }
            onEndShift();
          }}
        />
      )}

      {archived.length > 0 && (
        <>
          <div className="section-label">Recent shifts</div>
          <div className="stat-card">
            {archived.slice(0, 12).map((s) => (
              <div className="stat" key={s.id}>
                <span className="stat__label">{format(new Date(s.startedAt), 'MMM d')}</span>
                <span className="stat__detail tabular">
                  {fmtClockLong(s.startedAt)} – {s.endedAt ? fmtClockLong(s.endedAt) : '—'} ·{' '}
                  {sinceISO(s.startedAt, new Date(s.endedAt ?? s.startedAt).getTime())}
                </span>
              </div>
            ))}
          </div>
        </>
      )}
    </>
  );
}
