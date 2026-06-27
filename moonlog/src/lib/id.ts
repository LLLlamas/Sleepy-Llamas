// Small id + clock helpers. crypto.randomUUID is available in all PWA-capable
// browsers (iOS 15.4+, modern Chrome); fall back just in case.
export function uid(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID();
  }
  return 'id-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
}

export function nowISO(): string {
  return new Date().toISOString();
}
