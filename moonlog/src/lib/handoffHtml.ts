import { format } from 'date-fns';
import type {
  Baby,
  FeedEvent,
  FeedMethod,
  LogEvent,
  NoteEvent,
  Shift,
  SleepSession,
} from '../db/types';
import { computeTotals } from './summary';
import { fmtClockLong, fmtDuration, fmtShortMin, spanMinutes } from './time';
import { formatAmount, type Unit } from './units';
import { STOOL_LABEL, isBottle, tagLabel } from './labels';

/**
 * Sleepy-Llamas-themed printable handoff page. Self-contained HTML (only an
 * optional Google-Fonts link, with system fallbacks) so it opens in any browser
 * and "Save as PDF" prints cleanly. Designed as a keepsake the parents keep —
 * distinct from the plain-text "Copy" summary that pastes into Messages.
 */

const escapeHtml = (s: string): string =>
  s.replace(/[&<>"']/g, (c) =>
    c === '&' ? '&amp;' : c === '<' ? '&lt;' : c === '>' ? '&gt;' : c === '"' ? '&quot;' : '&#39;',
  );

const WARM_METHOD: Record<FeedMethod, string> = {
  'breast-left': 'left breast',
  'breast-right': 'right breast',
  'bottle-breastmilk': 'bottle, breastmilk',
  'bottle-formula': 'bottle, formula',
};

function feedDesc(ev: FeedEvent, unit: Unit): string {
  if (isBottle(ev.method) && ev.amountMl != null) {
    return `${WARM_METHOD[ev.method]} — ${formatAmount(ev.amountMl, unit)}`;
  }
  return WARM_METHOD[ev.method];
}

function noteDesc(ev: NoteEvent): string {
  const parts: string[] = [];
  if (ev.text) parts.push(ev.text);
  if (ev.tempF != null) parts.push(`temp ${ev.tempF}°F`);
  if (ev.tags?.length) {
    const extra = ev.tags.filter((t) => t !== 'temp').map(tagLabel);
    if (extra.length) parts.push(extra.join(', '));
  }
  return parts.join(' · ') || 'Note';
}

const liRow = (time: string, desc: string): string =>
  `<li><span class="t">${escapeHtml(time)}</span> <span class="d">${escapeHtml(desc)}</span></li>`;

const emptyRow = (text: string): string =>
  `<li><span class="d" style="color:var(--muted);font-style:italic">${escapeHtml(text)}</span></li>`;

export function buildHandoffHtml(
  baby: Baby,
  shift: Shift,
  events: LogEvent[],
  sleepSessions: SleepSession[],
  unit: Unit,
  now: number,
  fontCss = '',
): string {
  const totals = computeTotals(events, sleepSessions, now);
  const sorted = [...events].sort((a, b) => new Date(a.at).getTime() - new Date(b.at).getTime());
  const startMs = new Date(shift.startedAt).getTime();
  const endMs = shift.endedAt ? new Date(shift.endedAt).getTime() : now;

  const feeds = sorted.filter((e): e is FeedEvent => e.type === 'feed');
  const notes = sorted.filter((e): e is NoteEvent => e.type === 'note');
  const sleeps = [...sleepSessions].sort(
    (a, b) => new Date(a.startAt).getTime() - new Date(b.startAt).getTime(),
  );

  const feedRows = feeds.length
    ? feeds.map((ev) => liRow(fmtClockLong(ev.at), feedDesc(ev, unit))).join('\n        ')
    : emptyRow('No feeds logged this shift.');

  const sleepRows = sleeps.length
    ? sleeps
        .map((s) => {
          const tail = s.endAt
            ? `→ ${fmtClockLong(s.endAt)} · ${fmtShortMin(spanMinutes(s.startAt, s.endAt))}`
            : `still asleep · ${fmtShortMin(spanMinutes(s.startAt, now))} so far`;
          return liRow(fmtClockLong(s.startAt), tail);
        })
        .join('\n        ')
    : emptyRow('No sleep logged this shift.');

  const noteRows = notes
    .map((ev) => liRow(fmtClockLong(ev.at), noteDesc(ev)))
    .join('\n        ');

  const feedVolume = totals.feedMl ? `about ${formatAmount(totals.feedMl, unit)}` : '';
  const feedVolumeTag = feedVolume ? ` &middot; ${feedVolume}` : '';
  const prog = totals.stoolProgression.map((s) => STOOL_LABEL[s].toLowerCase()).join(' → ');

  const notesSection =
    totals.notes > 0
      ? `<section class="section notes">
      <div class="section-head">
        <h2>Notes from the night</h2>
        <span class="rule"></span>
        <span class="tag"><span class="pip"></span>${totals.notes} noted</span>
      </div>
      <ul class="timeline note-list">
        ${noteRows}
      </ul>
    </section>`
      : '';

  const tokens: Record<string, string> = {
    fontFaces: fontCss,
    babyName: escapeHtml(baby.name),
    dateLabel: format(new Date(startMs), 'EEEE, MMMM d'),
    startTime: fmtClockLong(startMs),
    endTime: shift.endedAt ? fmtClockLong(endMs) : 'now',
    shiftLength: fmtDuration(endMs - startMs),
    caregiver: escapeHtml(shift.caregiver ?? ''),
    feedCount: String(totals.feeds),
    feedVolume,
    feedVolumeTag,
    diaperCount: String(totals.diapers),
    wetCount: String(totals.wet),
    dirtyCount: String(totals.dirty),
    stoolProgression: prog ? `stool: ${prog}` : '',
    sleepTotal: fmtShortMin(totals.sleepMin),
    sleepStretches: String(totals.stretches),
    longestStretch: totals.longestMin ? fmtShortMin(totals.longestMin) : '—',
    noteCount: String(totals.notes),
    feedRows,
    sleepRows,
    notesSection,
    generatedNote: 'Logged with Moonlog · Sleepy Llamas',
  };

  return TEMPLATE.replace(/\{\{(\w+)\}\}/g, (_, key: string) =>
    key in tokens ? tokens[key] : '',
  );
}

const TEMPLATE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Moonlog — {{babyName}}'s Night · {{dateLabel}}</title>
<style>{{fontFaces}}
  :root{
    --page:#fdf6f4;
    --card:#fffaf5;
    --panel:#f7e6e2;
    --chip:#f3ddd6;
    --ink:#2a1418;
    --muted:#6b4a4f;
    --hair:rgba(61,15,23,0.12);
    --maroon:#a83246;
    --maroon-deep:#6b1a28;
    --gold:#c79a5e;
    --gold-soft:#d9a96b;
    --green:#3f7d68;
    --rose:#b0506a;
    --serif:"Fraunces", Georgia, "Times New Roman", serif;
    --sans:"Inter", -apple-system, system-ui, sans-serif;
  }

  *{box-sizing:border-box;}

  html,body{margin:0;padding:0;}

  body{
    background:var(--page);
    color:var(--ink);
    font-family:var(--sans);
    line-height:1.55;
    -webkit-font-smoothing:antialiased;
    text-rendering:optimizeLegibility;
    padding:0 18px 64px;
  }

  .sheet{
    max-width:640px;
    margin:0 auto;
  }

  /* ---------- Refined gold gradient hairline (grafted from A) ---------- */
  .goldrule{
    height:1px;
    border:0;
    background:linear-gradient(90deg,
      rgba(199,154,94,0) 0%,
      var(--gold) 28%,
      var(--gold-soft) 50%,
      var(--gold) 72%,
      rgba(199,154,94,0) 100%);
    opacity:.9;
  }

  /* ---------- Save as PDF button ---------- */
  .save-bar{
    position:sticky;
    top:0;
    z-index:20;
    display:flex;
    justify-content:flex-end;
    padding:14px 0 6px;
    pointer-events:none;
  }
  .save-btn{
    pointer-events:auto;
    font-family:var(--sans);
    font-size:13px;
    font-weight:600;
    letter-spacing:.02em;
    color:var(--card);
    background:var(--maroon);
    border:1px solid var(--maroon-deep);
    border-radius:999px;
    padding:9px 18px;
    cursor:pointer;
    box-shadow:0 6px 18px rgba(107,26,40,0.22);
    transition:background .15s ease, transform .1s ease;
  }
  .save-btn:hover{background:var(--maroon-deep);}
  .save-btn:active{transform:translateY(1px);}
  .save-btn:focus-visible{
    outline:2px solid var(--maroon-deep);
    outline-offset:2px;
  }

  /* ---------- Night-sky header / keepsake card ---------- */
  .almanac{
    position:relative;
    overflow:hidden;
    border-radius:22px;
    border:1px solid var(--hair);
    background:
      radial-gradient(120% 90% at 78% 8%, rgba(199,154,94,0.16) 0%, rgba(199,154,94,0) 46%),
      radial-gradient(140% 120% at 18% 0%, rgba(176,80,106,0.14) 0%, rgba(176,80,106,0) 42%),
      linear-gradient(180deg, #f3e0db 0%, #f8eae5 52%, var(--card) 100%);
    padding:34px 26px 30px;
    box-shadow:0 14px 34px rgba(107,26,40,0.10);
  }

  /* decorative gold keepsake inset border (grafted from A) */
  .almanac::before{
    content:"";
    position:absolute;
    inset:9px;
    border:1px solid rgba(199,154,94,0.45);
    border-radius:15px;
    pointer-events:none;
  }

  /* tiny CSS-only stars, print safe (use real elements, no images) */
  .stars{position:absolute;inset:0;pointer-events:none;}
  .star{
    position:absolute;
    width:3px;height:3px;
    border-radius:50%;
    background:var(--gold);
    opacity:.55;
  }
  .star.sm{width:2px;height:2px;opacity:.4;}
  .star.lg{width:4px;height:4px;opacity:.5;}
  .star.s1{top:18px;left:8%;}
  .star.s2{top:40px;left:24%;}
  .star.s3{top:14px;left:46%;}
  .star.s4{top:54px;left:62%;}
  .star.s5{top:26px;left:88%;}
  .star.s6{top:66px;left:34%;}
  .star.s7{top:10px;left:72%;}
  .star.s8{top:78px;left:13%;}

  .crest{
    position:relative;
    display:flex;
    align-items:center;
    gap:10px;
    font-family:var(--sans);
    font-size:12px;
    font-weight:600;
    letter-spacing:.16em;
    text-transform:uppercase;
    color:var(--maroon-deep);
  }
  .crest .moon{
    width:26px;height:26px;display:block;flex:none;
  }
  .crest .brand{opacity:.9;}
  .crest .sep{opacity:.4;}

  .almanac h1{
    position:relative;
    font-family:var(--serif);
    font-weight:500;
    font-size:34px;
    line-height:1.12;
    margin:18px 0 4px;
    letter-spacing:-0.01em;
    color:var(--ink);
  }
  .almanac h1 .accent{font-style:italic;color:var(--maroon-deep);}

  .datestamp{
    position:relative;
    font-family:var(--serif);
    font-size:16px;
    color:var(--muted);
    margin:0 0 18px;
  }

  .shift-line{
    position:relative;
    display:flex;
    flex-wrap:wrap;
    align-items:baseline;
    gap:10px 14px;
    padding-top:16px;
    border-top:1px solid var(--hair);
    font-size:14px;
    color:var(--muted);
  }
  .shift-line .span{
    font-weight:600;
    color:var(--ink);
  }
  .shift-line .arrow{color:var(--gold);font-weight:600;}
  .shift-line .len{
    margin-left:auto;
    font-family:var(--serif);
    font-size:15px;
    color:var(--maroon-deep);
  }
  .shift-line .len strong{font-weight:600;}

  /* ---------- Lead letter (warmer, grafted from A) ---------- */
  .letter{
    margin:26px 2px 4px;
  }
  .letter .lede-moon{color:var(--gold-soft);font-size:19px;}
  .letter p{
    font-family:var(--serif);
    font-size:17px;
    line-height:1.55;
    color:var(--ink);
    margin:0 0 12px;
  }
  .letter p:last-child{margin-bottom:0;}
  .letter .signoff{
    font-style:italic;
    font-size:16px;
    color:var(--muted);
    margin-top:14px;
  }
  .letter .signoff .name{
    color:var(--maroon-deep);
    font-style:normal;
    font-weight:600;
  }
  /* hide the signoff name span when caregiver is empty */
  .letter .signoff .name:empty{display:none;}

  /* ---------- Stat grid ---------- */
  .stats{
    display:grid;
    grid-template-columns:repeat(2,1fr);
    gap:12px;
    margin:24px 0 6px;
  }
  .stat{
    position:relative;
    background:var(--card);
    border:1px solid var(--hair);
    border-top:3px solid var(--gold);
    border-radius:16px;
    padding:15px 16px 14px;
  }
  .stat.feeds{border-top-color:var(--rose);}
  .stat.diapers{border-top-color:var(--gold);}
  .stat.sleep{border-top-color:var(--green);}
  .stat.notes{border-top-color:var(--maroon);}

  .stat .label{
    display:flex;
    align-items:center;
    gap:8px;
    font-size:11px;
    font-weight:600;
    letter-spacing:.13em;
    text-transform:uppercase;
    color:var(--muted);
    margin-bottom:8px;
  }
  .stat .ico{
    width:17px;height:17px;flex:none;display:block;
  }
  .stat.feeds .ico{color:var(--rose);}
  .stat.diapers .ico{color:#9a7536;}
  .stat.sleep .ico{color:var(--green);}
  .stat.notes .ico{color:var(--maroon);}
  .stat .big{
    font-family:var(--serif);
    font-size:30px;
    font-weight:500;
    line-height:1;
    color:var(--ink);
  }
  .stat .big .unit{font-size:14px;color:var(--muted);font-family:var(--sans);font-weight:500;margin-left:3px;}
  .stat .sub{
    margin-top:7px;
    font-size:12.5px;
    color:var(--muted);
    line-height:1.4;
  }
  .stat .sub:empty{display:none;}

  /* ---------- Section blocks ---------- */
  .section{margin:30px 0 0;}
  .section-head{
    display:flex;
    align-items:baseline;
    gap:12px;
    margin:0 2px 14px;
  }
  .section-head h2{
    font-family:var(--serif);
    font-weight:500;
    font-size:21px;
    margin:0;
    color:var(--ink);
    white-space:nowrap;
  }
  .section-head .rule{
    flex:1;
    height:1px;
    align-self:center;
    background:linear-gradient(90deg,
      rgba(199,154,94,0) 0%,
      var(--gold) 22%,
      var(--gold-soft) 55%,
      var(--gold) 80%,
      rgba(199,154,94,0) 100%);
    opacity:.85;
  }
  .section-head .tag{
    font-size:12px;
    color:var(--muted);
    white-space:nowrap;
  }
  .section-head .tag .pip{
    display:inline-block;width:7px;height:7px;border-radius:50%;
    margin-right:5px;vertical-align:middle;
  }
  .section.feeds .pip{background:var(--rose);}
  .section.sleep .pip{background:var(--green);}
  .section.notes .pip{background:var(--maroon);}

  .timeline{
    list-style:none;
    margin:0;
    padding:6px 18px;
    background:var(--card);
    border:1px solid var(--hair);
    border-radius:16px;
  }
  .timeline li{
    display:flex;
    align-items:baseline;
    gap:14px;
    padding:11px 0;
    border-bottom:1px solid var(--hair);
    font-size:14.5px;
  }
  .timeline li:last-child{border-bottom:0;}
  .timeline .t{
    flex:none;
    width:78px;
    font-variant-numeric:tabular-nums;
    font-feature-settings:"tnum" 1;
    font-weight:600;
    font-size:13px;
    color:var(--maroon-deep);
    letter-spacing:.01em;
  }
  .timeline .d{
    flex:1;
    color:var(--ink);
  }
  .timeline.note-list .d{color:var(--ink);}
  .timeline.note-list li{font-family:var(--serif);font-size:15px;line-height:1.5;}
  .timeline.note-list .t{font-family:var(--sans);}

  .sleep-highlight{
    margin:0 2px 14px;
    display:flex;
    flex-wrap:wrap;
    gap:8px 10px;
  }
  .pill{
    font-size:12.5px;
    color:var(--muted);
    background:var(--panel);
    border:1px solid var(--hair);
    border-radius:999px;
    padding:6px 13px;
  }
  .pill strong{color:var(--green);font-weight:600;}
  .pill.diaper strong{color:var(--maroon-deep);}
  .pill.empty:empty{display:none;}

  /* ---------- Footer ---------- */
  .closer{
    margin:34px 2px 0;
    padding-top:22px;
    text-align:center;
  }
  .closer .keepsake{
    font-family:var(--serif);
    font-style:italic;
    font-size:15px;
    color:var(--muted);
    margin:18px 0 14px;
  }
  .closer .gen{
    display:inline-flex;
    align-items:center;
    gap:7px;
    font-size:12px;
    letter-spacing:.04em;
    color:var(--muted);
  }
  .closer .gen .moon{width:15px;height:15px;}

  /* ---------- Print tuning ---------- */
  @media print{
    @page{margin:14mm;}
    html,body{background:#fffaf5;padding:0;}
    body{font-size:11.5pt;}
    .no-print{display:none !important;}
    .sheet{max-width:none;}
    .almanac,.stat,.timeline{
      box-shadow:none !important;
      break-inside:avoid;
    }
    .section,.stats{break-inside:avoid;}
    .timeline li{break-inside:avoid;}
    .almanac{
      border-color:rgba(61,15,23,0.18);
    }
    *{
      -webkit-print-color-adjust:exact;
      print-color-adjust:exact;
    }
  }
</style>
</head>
<body>
  <div class="sheet">

    <div class="save-bar no-print">
      <button class="save-btn" type="button" onclick="window.print()">Save as PDF</button>
    </div>

    <!-- ===== Almanac header / keepsake card ===== -->
    <header class="almanac">
      <div class="stars" aria-hidden="true">
        <span class="star sm s1"></span>
        <span class="star s2"></span>
        <span class="star lg s3"></span>
        <span class="star sm s4"></span>
        <span class="star s5"></span>
        <span class="star sm s6"></span>
        <span class="star s7"></span>
        <span class="star lg s8"></span>
      </div>

      <div class="crest">
        <svg class="moon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M20 14.2A8.2 8.2 0 1 1 10.6 4a6.4 6.4 0 0 0 9.4 10.2z"
                fill="none" stroke="#6b1a28" stroke-width="1.5" stroke-linejoin="round"/>
        </svg>
        <span class="brand">Moonlog</span>
        <span class="sep">·</span>
        <span class="brand">Sleepy&nbsp;Llamas</span>
      </div>

      <h1>{{babyName}}&rsquo;s <span class="accent">night</span></h1>
      <p class="datestamp">{{dateLabel}}</p>

      <div class="shift-line">
        <span><span class="span">{{startTime}}</span> <span class="arrow">&rarr;</span> <span class="span">{{endTime}}</span></span>
        <span class="len"><strong>{{shiftLength}}</strong> on watch</span>
      </div>
    </header>

    <!-- ===== Lead letter ===== -->
    <div class="letter">
      <p><span class="lede-moon">&#9789;</span> Good morning. {{babyName}} is settled and in good hands &mdash; here&rsquo;s the whole night, gathered for you.</p>
      <p>Everything below is logged just as it happened: the feeds, the changes, the stretches of sleep, and the little moments worth remembering. Pour your coffee, take a slow read, and rest knowing the night was watched over.</p>
      <p class="signoff">With care,<br><span class="name">{{caregiver}}</span></p>
    </div>

    <!-- ===== Stat summary ===== -->
    <section class="stats" aria-label="Night summary">
      <div class="stat feeds">
        <div class="label">
          <svg class="ico" viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path d="M9.5 3h5M10 3v2.2c0 .6-.25 1.18-.7 1.6L8 8.3C7.36 8.9 7 9.74 7 10.62V19a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2v-8.38c0-.88-.36-1.72-1-2.32l-1.3-1.5A2.2 2.2 0 0 1 16 5.2V3"
                  stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
            <path d="M7 12.5h10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
          </svg>
          Feeds
        </div>
        <div class="big">{{feedCount}}</div>
        <div class="sub">{{feedVolume}}</div>
      </div>

      <div class="stat diapers">
        <div class="label">
          <svg class="ico" viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path d="M3 6h18v3c0 5-3.8 9-9 9S3 14 3 9V6z"
                  stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>
            <path d="M3 9c3 0 5 1.6 9 1.6S18 9 21 9" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
          Diapers
        </div>
        <div class="big">{{diaperCount}}</div>
        <div class="sub">{{wetCount}} wet &middot; {{dirtyCount}} dirty</div>
      </div>

      <div class="stat sleep">
        <div class="label">
          <svg class="ico" viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path d="M20 14.2A8.2 8.2 0 1 1 10.6 4a6.4 6.4 0 0 0 9.4 10.2z"
                  stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>
          </svg>
          Sleep
        </div>
        <div class="big">{{sleepTotal}}</div>
        <div class="sub">{{sleepStretches}} stretches &middot; longest {{longestStretch}}</div>
      </div>

      <div class="stat notes">
        <div class="label">
          <svg class="ico" viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path d="M6 3h8l4 4v14a0 0 0 0 1 0 0H6a0 0 0 0 1 0 0V3z"
                  stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>
            <path d="M13 3v5h5M8.5 12.5h7M8.5 16h7" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
          Notes
        </div>
        <div class="big">{{noteCount}}</div>
        <div class="sub">moments worth keeping</div>
      </div>
    </section>

    <!-- ===== Feeds ===== -->
    <section class="section feeds">
      <div class="section-head">
        <h2>Feeds</h2>
        <span class="rule"></span>
        <span class="tag"><span class="pip"></span>{{feedCount}} total{{feedVolumeTag}}</span>
      </div>
      <ul class="timeline">
        {{feedRows}}
      </ul>
    </section>

    <!-- ===== Diapers ===== -->
    <section class="section diapers">
      <div class="section-head">
        <h2>Diapers</h2>
        <span class="rule"></span>
        <span class="tag">{{wetCount}} wet &middot; {{dirtyCount}} dirty</span>
      </div>
      <div class="sleep-highlight">
        <span class="pill diaper"><strong>{{diaperCount}}</strong>&nbsp;changes in all</span>
        <span class="pill empty">{{stoolProgression}}</span>
      </div>
    </section>

    <!-- ===== Sleep ===== -->
    <section class="section sleep">
      <div class="section-head">
        <h2>Sleep</h2>
        <span class="rule"></span>
        <span class="tag"><span class="pip"></span>{{sleepTotal}} total rest</span>
      </div>
      <div class="sleep-highlight">
        <span class="pill"><strong>{{sleepTotal}}</strong>&nbsp;asleep</span>
        <span class="pill">{{sleepStretches}}&nbsp;stretches</span>
        <span class="pill">longest&nbsp;<strong>{{longestStretch}}</strong></span>
      </div>
      <ul class="timeline">
        {{sleepRows}}
      </ul>
    </section>

    {{notesSection}}

    <!-- ===== Closer ===== -->
    <footer class="closer">
      <hr class="goldrule" aria-hidden="true">
      <p class="keepsake">Rest easy &mdash; the night is logged and the morning is yours.</p>
      <span class="gen">
        <svg class="moon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M20 14.2A8.2 8.2 0 1 1 10.6 4a6.4 6.4 0 0 0 9.4 10.2z"
                fill="none" stroke="#6b4a4f" stroke-width="1.6" stroke-linejoin="round"/>
        </svg>
        {{generatedNote}}
      </span>
    </footer>

  </div>
</body>
</html>`;
