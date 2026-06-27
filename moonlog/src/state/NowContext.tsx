import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from 'react';

// A single app-level clock. All relative times + the running sleep timer read
// from this one tick (spec §4) rather than each spinning up their own.
const NowCtx = createContext<number>(Date.now());

export function NowProvider({ children }: { children: ReactNode }) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const tick = () => setNow(Date.now());
    const id = window.setInterval(tick, 30_000);
    // re-sync immediately when the app returns to foreground
    const onVis = () => {
      if (document.visibilityState === 'visible') tick();
    };
    document.addEventListener('visibilitychange', onVis);
    return () => {
      window.clearInterval(id);
      document.removeEventListener('visibilitychange', onVis);
    };
  }, []);

  return <NowCtx.Provider value={now}>{children}</NowCtx.Provider>;
}

export function useNow(): number {
  return useContext(NowCtx);
}
