import type {
  DiaperContents,
  FeedMethod,
  LogEvent,
  StoolColor,
} from '../db/types';
import { fmtShortMin } from './time';
import { formatAmount, type Unit } from './units';

export const METHOD_LABEL: Record<FeedMethod, string> = {
  'breast-left': 'Breast L',
  'breast-right': 'Breast R',
  'bottle-breastmilk': 'Bottle — breastmilk',
  'bottle-formula': 'Bottle — formula',
};

// compact form used in summaries: "Bottle/breastmilk", "Breast L"
export const METHOD_LABEL_SHORT: Record<FeedMethod, string> = {
  'breast-left': 'Breast L',
  'breast-right': 'Breast R',
  'bottle-breastmilk': 'Bottle/breastmilk',
  'bottle-formula': 'Bottle/formula',
};

export const CONTENTS_LABEL: Record<DiaperContents, string> = {
  wet: 'Wet',
  dirty: 'Dirty',
  both: 'Both',
};

export const STOOL_LABEL: Record<StoolColor, string> = {
  meconium: 'Meconium',
  transitional: 'Transitional',
  green: 'Green',
  brown: 'Brown',
  yellow: 'Yellow',
};

// visual swatch colors (true-to-life-ish, for the stool color picker)
export const STOOL_SWATCH: Record<StoolColor, string> = {
  meconium: '#1c1a17',
  transitional: '#5f5230',
  green: '#5f6e34',
  brown: '#6e4a2a',
  yellow: '#d2a93f',
};

export const STOOL_ORDER: StoolColor[] = [
  'meconium',
  'transitional',
  'green',
  'brown',
  'yellow',
];

export function isBottle(method: FeedMethod): boolean {
  return method === 'bottle-breastmilk' || method === 'bottle-formula';
}

export function feedLabel(method: FeedMethod, amountMl: number | undefined, unit: Unit): string {
  const base = METHOD_LABEL_SHORT[method];
  if (isBottle(method) && amountMl != null) return `${base} ${formatAmount(amountMl, unit)}`;
  return base;
}

export function diaperLabel(contents: DiaperContents, stool?: StoolColor): string {
  const base = CONTENTS_LABEL[contents];
  if (stool && (contents === 'dirty' || contents === 'both')) {
    return `${base} · ${STOOL_LABEL[stool].toLowerCase()}`;
  }
  return base;
}

export function eventIcon(type: LogEvent['type']): string {
  switch (type) {
    case 'feed':
      return '🍼';
    case 'diaper':
      return '🧷';
    case 'note':
      return '📝';
  }
}

// one-line timeline summary for any event
export function eventSummary(ev: LogEvent, unit: Unit): string {
  switch (ev.type) {
    case 'feed': {
      const dur = ev.durationMin ? ` · ${fmtShortMin(ev.durationMin)}` : '';
      return feedLabel(ev.method, ev.amountMl, unit) + dur;
    }
    case 'diaper':
      return diaperLabel(ev.contents, ev.stool);
    case 'note': {
      if (ev.text) return ev.text;
      if (ev.tempF != null) return `Temp ${ev.tempF}°F`;
      if (ev.tags && ev.tags.length) return ev.tags.map(tagLabel).join(', ');
      return 'Note';
    }
  }
}

export function tagLabel(tag: string): string {
  const map: Record<string, string> = {
    'spit-up': 'Spit-up',
    fussy: 'Fussy',
    jaundice: 'Jaundice watch',
    pumped: 'Pumped',
    temp: 'Temp',
  };
  return map[tag] ?? tag;
}
