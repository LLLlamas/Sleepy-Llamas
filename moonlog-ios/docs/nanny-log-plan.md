# Reminder consolidation and daytime handoff plan

Prepared November 16, 2026. This is the implementation and acceptance contract;
`status.md` records current results and limitations. User scope: consolidate the
older reminder work into the newer native app, then build daytime Nanny Log with
editable EOD summaries and notes. Parent acknowledgement is optional and happens
on the same phone first.

## Preserve the current app

Use the later `moonlog-ios` source as the base. Selectively port reminder and
remembered shift-hour behavior from `moonlog-reminders-watch`; do not replace
whole older files. Preserve Note reachability, live relationship accessors,
transactional CareStore writes, Undo and the later logging/handoff fixes. The
native branch must never merge into the website's `main`; the website and frozen
PWA are outside this work. No TestFlight upload is part of this implementation.

## Work ownership

- Lead: model and CareStore integration, deterministic factual report digest,
  day/night setup and navigation, editor/review/published handoff UI, integration.
- Reminder agent: notifications, feed reminder controls/countdowns, lifecycle
  reconciliation and remembered family shift-hour defaults, focused tests.
- Report core/research agent: pure versioned report values and lifecycle tests,
  day-aware text/HTML output, focused primary-source research and this plan.
- Root: independent integration/audit pass and final validation coordination.

Workers coordinate changes at file boundaries. Simulator runners are serialized.
No agent commits or pushes until the owner/root chooses a native-only sync.

## Persisted product model

Keep one native app and one family-scoped log, with an explicit day/night context
on each shift. Existing shifts default to night; appearance does not determine
context. Day mode uses neutral daytime copy and the existing core care records;
structured note tags can cover outings, play, comfort and supplies without a new
unbounded collection of event kinds.

Persist `DayReportState` on its owning shift through CareStore. It contains an
editable `DayReportDraft`, immutable publication history and optional revision-bound
local acknowledgements. No new cloud schema or remote identity is implied. Source
fingerprints use canonical factual input and a stable digest, not Swift `Hasher`;
a completed report must not become stale merely because a screen clock ticks.

Draft fields: caregiver name, personal summary, practical handoff/evening notes,
open questions. Require a closed shift before publication so coverage is explicit.
Review factual totals and recorded timeline alongside the narrative. Save a local
published version only after explicit caregiver action. Failed writes keep the
entered draft and surface an honest retry path.

Copy/share exports the selected frozen publication, not a later silently recomputed
report. Record an optional same-phone parent acknowledgement with a typed name,
parent note and time only for the current reviewed revision. Label it as recorded
on this phone with unverified identity. Acknowledgement never blocks any care or
handoff workflow and never implies clinical consent or agreement with every fact.

## Acceptance checks

1. Legacy shifts open in night mode with existing log/history/share controls intact.
2. Day mode can be selected before logging and is visible on the active shift.
3. Feed reminders do not lose saved feeds when permission or scheduling fails;
   corrections and lifecycle changes reconcile pending requests consistently.
4. Draft notes survive a successful save and reopening the report/family context.
5. Publishing the same source and normalized draft twice returns the same revision.
6. Editing narrative or care records makes any old acknowledgement historical;
   publication snapshots and historical receipts remain intact.
7. Parent acknowledgement is optional, explicitly local, revision/date scoped, and
   stores a parent response separately from the caregiver's narrative.
8. Day output says day, labels shift-only coverage, preserves unknown feed amounts,
   escapes personal text in HTML and keeps a useful readable detailed care log.
9. Reports assemble the owning family's records; invalid/stale report operations
   fail without partial mutation.
10. Unit/persistence tests plus actual UI reachability cover the new routes. Record
    real-device notification and remote-sharing limits separately from test passes.

## Remaining phases

First pilot this local workflow with consenting families and synthetic demonstrations.
Backup/restore and draft recovery require their own explicit acceptance checks;
published share documents are not backups. Secure remote parent reports need
individual identity, household authorization, invitations/revocation and tested
cross-device persistence. Live multi-caregiver writes, a Watch app, subscriptions
and AI rewriting are later work, not implied by the local handoff MVP.
