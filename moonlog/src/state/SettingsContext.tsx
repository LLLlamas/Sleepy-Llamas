import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import type { FeedMethod } from '../db/types';
import type { Unit } from '../lib/units';

export type ThemeName = 'night' | 'deep-night' | 'day';

export interface Settings {
  theme: ThemeName;
  unit: Unit;
  feedDefault: FeedMethod;
  dueSoonHours: number;
  tempUnit: 'F' | 'C';
  caregiver: string;
  keepAwake: boolean;
  iosHintDismissed: boolean;
}

const DEFAULTS: Settings = {
  theme: 'night',
  unit: 'oz',
  feedDefault: 'breast-left',
  dueSoonHours: 3,
  tempUnit: 'F',
  caregiver: '',
  keepAwake: false,
  iosHintDismissed: false,
};

const KEY = 'moonlog.settings';
const THEME_KEY = 'moonlog.theme'; // mirrored for the pre-paint init script

// theme-color meta per theme so the iOS status bar / chrome matches
const THEME_COLOR: Record<ThemeName, string> = {
  night: '#1a0a0e',
  'deep-night': '#100508',
  day: '#fdf6f4',
};

function load(): Settings {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) return { ...DEFAULTS, ...JSON.parse(raw) };
  } catch {
    /* ignore */
  }
  return DEFAULTS;
}

interface Ctx {
  settings: Settings;
  update: (patch: Partial<Settings>) => void;
}

const SettingsCtx = createContext<Ctx | null>(null);

export function SettingsProvider({ children }: { children: ReactNode }) {
  const [settings, setSettings] = useState<Settings>(load);

  // persist + apply theme to <html> and the theme-color meta
  useEffect(() => {
    try {
      localStorage.setItem(KEY, JSON.stringify(settings));
      localStorage.setItem(THEME_KEY, settings.theme);
    } catch {
      /* ignore */
    }
    document.documentElement.setAttribute('data-theme', settings.theme);
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', THEME_COLOR[settings.theme]);
  }, [settings]);

  const update = useCallback((patch: Partial<Settings>) => {
    setSettings((prev) => ({ ...prev, ...patch }));
  }, []);

  const value = useMemo(() => ({ settings, update }), [settings, update]);
  return <SettingsCtx.Provider value={value}>{children}</SettingsCtx.Provider>;
}

export function useSettings(): Ctx {
  const ctx = useContext(SettingsCtx);
  if (!ctx) throw new Error('useSettings must be used within SettingsProvider');
  return ctx;
}
