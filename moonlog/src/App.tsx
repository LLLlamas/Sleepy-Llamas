import { useEffect, useRef, useState } from 'react';
import { Header } from './components/Header';
import { QuickActions } from './components/QuickActions';
import { TabBar, type TabId } from './components/TabBar';
import { Tonight } from './screens/Tonight';
import { Summary } from './screens/Summary';
import { Settings } from './screens/Settings';
import { Onboarding } from './screens/Onboarding';
import { FeedSheet } from './components/sheets/FeedSheet';
import { DiaperSheet } from './components/sheets/DiaperSheet';
import { NoteSheet } from './components/sheets/NoteSheet';
import { SleepSheet } from './components/sheets/SleepSheet';
import {
  useBabies,
  useActiveShifts,
  useEvents,
  useSleepSessions,
  useOpenSleep,
  useLastFeedMethod,
  ensureActiveShift,
  endShiftAndStartFresh,
  toggleSleep,
  undoSleepToggle,
} from './db/hooks';
import { useNow } from './state/NowContext';
import { useSettings } from './state/SettingsContext';
import { useToast } from './state/ToastContext';
import { buzz } from './lib/haptics';
import type {
  DiaperEvent,
  FeedEvent,
  LogEvent,
  NoteEvent,
  SleepSession,
} from './db/types';

type SheetState =
  | { k: 'feed'; editing?: FeedEvent }
  | { k: 'diaper'; editing?: DiaperEvent }
  | { k: 'note'; editing?: NoteEvent }
  | { k: 'sleep'; editing?: SleepSession }
  | null;

const EMPTY: never[] = [];

export default function App() {
  const now = useNow();
  const { settings } = useSettings();
  const { showToast } = useToast();

  const babies = useBabies();
  const baby = babies?.[0];
  const babiesLoaded = babies !== undefined;

  const shifts = useActiveShifts(baby?.id);
  const shift = shifts?.[0];

  const events = useEvents(shift?.id) ?? EMPTY;
  const sleepSessions = useSleepSessions(shift?.id) ?? EMPTY;
  const openSleep = useOpenSleep(shift?.id);
  const lastMethod = useLastFeedMethod(shift?.id);

  const [tab, setTab] = useState<TabId>('tonight');
  const [sheet, setSheet] = useState<SheetState>(null);

  // ask for persistent storage once (spec §8: iOS may evict IndexedDB)
  useEffect(() => {
    navigator.storage?.persist?.().catch(() => {});
  }, []);

  // ensure an active shift exists once a baby is present
  const creating = useRef(false);
  useEffect(() => {
    if (baby && shifts !== undefined && shifts.length === 0 && !creating.current) {
      creating.current = true;
      ensureActiveShift(baby.id, settings.caregiver || undefined).finally(() => {
        creating.current = false;
      });
    }
  }, [baby, shifts, settings.caregiver]);

  const onToggleSleep = async () => {
    if (!shift) return;
    const r = await toggleSleep(shift.id);
    buzz();
    showToast(r.action === 'opened' ? 'Asleep — timer started' : 'Awake logged', {
      undo: () => undoSleepToggle(r),
    });
  };

  const onEndShift = async () => {
    if (!baby || !shift) return;
    await endShiftAndStartFresh(baby.id, shift.id, settings.caregiver || undefined);
    buzz();
    showToast('Shift ended — fresh shift started');
    setTab('tonight');
  };

  const editEvent = (ev: LogEvent) => {
    if (ev.type === 'feed') setSheet({ k: 'feed', editing: ev });
    else if (ev.type === 'diaper') setSheet({ k: 'diaper', editing: ev });
    else setSheet({ k: 'note', editing: ev });
  };
  const editSleep = (s: SleepSession) => setSheet({ k: 'sleep', editing: s });
  const closeSheet = () => setSheet(null);

  // ----- loading / first-run -----
  if (!babiesLoaded) {
    return <div className="app" aria-busy="true" />;
  }
  if (!baby) {
    return <Onboarding />;
  }
  if (!shift) {
    return (
      <div className="app">
        <div className="app__scroll">
          <div className="empty">
            <span className="moon" aria-hidden="true">🌙</span>
            Starting tonight's shift…
          </div>
        </div>
      </div>
    );
  }

  const showHeader = tab === 'tonight';

  return (
    <div className="app">
      {showHeader && <Header baby={baby} shift={shift} now={now} />}

      <div
        className="app__scroll"
        style={showHeader ? undefined : { paddingTop: 'calc(env(safe-area-inset-top) + 10px)' }}
      >
        {tab === 'tonight' && (
          <Tonight
            events={events}
            sleepSessions={sleepSessions}
            openSleep={openSleep}
            now={now}
            unit={settings.unit}
            dueSoonHours={settings.dueSoonHours}
            onToggleSleep={onToggleSleep}
            onEditEvent={editEvent}
            onEditSleep={editSleep}
          />
        )}
        {tab === 'summary' && (
          <Summary
            baby={baby}
            shift={shift}
            events={events}
            sleepSessions={sleepSessions}
            now={now}
            unit={settings.unit}
            onEndShift={onEndShift}
          />
        )}
        {tab === 'settings' && <Settings baby={baby} shift={shift} now={now} />}
      </div>

      <div className="dock">
        {tab === 'tonight' && (
          <QuickActions
            isAsleep={!!openSleep}
            onFeed={() => setSheet({ k: 'feed' })}
            onDiaper={() => setSheet({ k: 'diaper' })}
            onSleepToggle={onToggleSleep}
            onSleepManual={() => setSheet({ k: 'sleep' })}
            onNote={() => setSheet({ k: 'note' })}
          />
        )}
        <TabBar active={tab} onChange={setTab} />
      </div>

      {sheet?.k === 'feed' && (
        <FeedSheet shiftId={shift.id} editing={sheet.editing} lastMethod={lastMethod} onClose={closeSheet} />
      )}
      {sheet?.k === 'diaper' && (
        <DiaperSheet shiftId={shift.id} editing={sheet.editing} onClose={closeSheet} />
      )}
      {sheet?.k === 'note' && (
        <NoteSheet shiftId={shift.id} editing={sheet.editing} onClose={closeSheet} />
      )}
      {sheet?.k === 'sleep' && (
        <SleepSheet shiftId={shift.id} editing={sheet.editing} onClose={closeSheet} />
      )}
    </div>
  );
}
