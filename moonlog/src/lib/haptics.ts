// Light haptic feedback on save/undo. Guarded — most iOS Safari builds ignore
// navigator.vibrate, so this silently no-ops there.
export function buzz(ms = 15): void {
  try {
    if (typeof navigator !== 'undefined' && 'vibrate' in navigator) {
      navigator.vibrate(ms);
    }
  } catch {
    /* unsupported — ignore */
  }
}
