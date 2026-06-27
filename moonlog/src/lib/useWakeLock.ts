import { useEffect } from 'react';

/**
 * Hold a screen wake lock while `enabled` and the app is visible, so the phone
 * doesn't dim/sleep mid-feed. Re-acquires when returning to foreground.
 * Degrades silently where unsupported (older iOS Safari) — spec §4.
 */
export function useWakeLock(enabled: boolean): void {
  useEffect(() => {
    if (!enabled || !('wakeLock' in navigator)) return;

    let sentinel: WakeLockSentinel | null = null;
    let cancelled = false;

    const acquire = async () => {
      if (cancelled || document.visibilityState !== 'visible') return;
      try {
        sentinel = await navigator.wakeLock.request('screen');
      } catch {
        /* user-agent denied (e.g. low battery) — ignore */
      }
    };
    const onVisibility = () => {
      if (document.visibilityState === 'visible') acquire();
    };

    acquire();
    document.addEventListener('visibilitychange', onVisibility);

    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', onVisibility);
      sentinel?.release().catch(() => {});
      sentinel = null;
    };
  }, [enabled]);
}
