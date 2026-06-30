import { useEffect, useState } from 'react';
import type { Baby, LogEvent, Shift, SleepSession } from '../db/types';
import type { Unit } from '../lib/units';
import { computeTotals, buildSummaryText } from '../lib/summary';
import { buildHandoffHtml } from '../lib/handoffHtml';
import { useRecentShifts } from '../db/hooks';
import { useToast } from '../state/ToastContext';
import { ConfirmDialog } from '../components/ui/ConfirmDialog';
import {
  fmtClockLong,
  fmtDuration,
  fmtShortMin,
  sinceISO,
} from '../lib/time';
import { formatAmount } from '../lib/units';
import { STOOL_LABEL } from '../lib/labels';
import { format, isSameDay } from 'date-fns';

const PencilIcon = () => (
  <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M12 20h9" />
    <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z" />
  </svg>
);

interface Props {
  baby: Baby;
  shift: Shift;
  events: LogEvent[];
  sleepSessions: SleepSession[];
  now: number;
  unit: Unit;
  onEndShift: () => void;
  onEditShiftStart: () => void;
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

export function Summary({ baby, shift, events, sleepSessions, now, unit, onEndShift, onEditShiftStart }: Props) {
  const { showToast } = useToast();
  const recent = useRecentShifts(baby.id);
  const totals = computeTotals(events, sleepSessions, now);
  const generated = buildSummaryText(baby, shift, events, sleepSessions, unit, now);

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
    showToast('Reset to the auto-generated summary');
  };

  const [confirmEnd, setConfirmEnd] = useState(false);

  const onCopy = async () => {
    const ok = await copyText(text);
    showToast(ok ? 'Summary copied' : 'Copy failed — select & copy manually');
  };
  // "Share" opens the Sleepy-Llamas-themed keepsake page in a new tab; from there
  // the client reads it in the browser or taps "Save as PDF". Distinct from the
  // plain-text "Copy" that pastes into Messages/Notes.
  const onShareHandoff = async () => {
    // fonts are embedded so the keepsake renders identically offline; lazy-loaded
    // so the ~130KB of woff2 never weighs down the app's initial bundle
    const { HANDOFF_FONT_CSS } = await import('../lib/handoffFonts');
    const html = buildHandoffHtml(baby, shift, events, sleepSessions, unit, now, HANDOFF_FONT_CSS);
    const blob = new Blob([html], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    const win = window.open(url, '_blank', 'noopener');
    if (!win) {
      // pop-up blocked (e.g. installed PWA) — fall back to a download link
      const a = document.createElement('a');
      a.href = url;
      a.target = '_blank';
      a.rel = 'noopener';
      a.download = `moonlog-${format(new Date(shift.startedAt), 'yyyy-MM-dd')}-${baby.name || 'handoff'}.html`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      showToast('Saved the handoff page — open it to view or Save as PDF');
    } else {
      showToast('Opened the handoff — Save as PDF from your browser');
    }
    window.setTimeout(() => URL.revokeObjectURL(url), 60000);
  };

  const stoolProgression = totals.stoolProgression.map((s) => STOOL_LABEL[s]).join(' → ');
  const startMs = new Date(shift.startedAt).getTime();
  const endMs = shift.endedAt ? new Date(shift.endedAt).getTime() : now;
  const dateLabel = format(new Date(startMs), 'EEEE, MMM d');
  const crossedMidnight = !isSameDay(new Date(startMs), new Date(endMs));
  const isEmpty = events.length === 0 && sleepSessions.length === 0;

  const archived = (recent ?? []).filter((s) => s.endedAt && s.id !== shift.id);

  return (
    <>
      <h1 className="screen-title">Shift summary</h1>
      <p className="screen-sub">{baby.name} · {dateLabel}</p>
      <button
        type="button"
        className="summary-shift"
        onClick={onEditShiftStart}
        aria-label={`Shift ${fmtClockLong(startMs)} to ${shift.endedAt ? fmtClockLong(endMs) : 'now'} — tap to adjust the start time`}
      >
        <span className="summary-shift__times tabular">
          {fmtClockLong(startMs)} – {shift.endedAt ? fmtClockLong(endMs) : 'now'}
          {crossedMidnight && <span className="summary-shift__next"> · +1 day</span>}
        </span>
        <span className="summary-shift__meta">
          <span className="summary-shift__len tabular">{fmtDuration(endMs - startMs)}</span>
          <span className="summary-shift__edit"><PencilIcon /> start</span>
        </span>
      </button>

      {isEmpty && (
        <p className="note-banner">Nothing logged this shift yet — the summary fills in as you log.</p>
      )}

      <div className="sum-stats">
        <div className="sum-stat sum-stat--feeds">
          <span className="sum-stat__label">Feeds</span>
          <span className="sum-stat__value tabular">{totals.feeds}</span>
          {totals.feedMl ? (
            <span className="sum-stat__sub">{formatAmount(totals.feedMl, unit)}</span>
          ) : null}
        </div>
        <div className="sum-stat sum-stat--diapers">
          <span className="sum-stat__label">Diapers</span>
          <span className="sum-stat__value tabular">{totals.diapers}</span>
          <span className="sum-stat__sub">{totals.wet} wet · {totals.dirty} dirty</span>
        </div>
        <div className="sum-stat sum-stat--sleep">
          <span className="sum-stat__label">Sleep</span>
          <span className="sum-stat__value tabular">{fmtShortMin(totals.sleepMin)}</span>
          <span className="sum-stat__sub">
            {totals.stretches} stretch{totals.stretches === 1 ? '' : 'es'}
            {totals.longestMin ? ` · longest ${fmtShortMin(totals.longestMin)}` : ''}
          </span>
        </div>
        <div className="sum-stat sum-stat--notes">
          <span className="sum-stat__label">Notes</span>
          <span className="sum-stat__value tabular">{totals.notes}</span>
          {totals.notes > 0 && (
            <span className="sum-stat__sub">moment{totals.notes === 1 ? '' : 's'} kept</span>
          )}
        </div>
      </div>
      {stoolProgression && (
        <p className="sum-stool">
          <span className="sum-stool__label">Stool</span> {stoolProgression}
        </p>
      )}

      <div className="btn-row">
        <button type="button" className="btn btn--ghost" onClick={onCopy}>
          Copy text
        </button>
        <button type="button" className="btn btn--primary" onClick={onShareHandoff}>
          Share handoff
        </button>
      </div>
      <p className="btn-row-hint">
        <strong>Copy</strong> pastes into Messages or Notes. <strong>Share</strong> opens a keepsake
        page to view or Save as PDF.
      </p>

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
