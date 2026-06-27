export type Unit = 'oz' | 'ml';

export const ML_PER_OZ = 29.5735;

export const mlToOz = (ml: number): number => ml / ML_PER_OZ;
export const ozToMl = (oz: number): number => oz * ML_PER_OZ;

// stepper increments per unit
export const STEP: Record<Unit, number> = { oz: 0.5, ml: 10 };

// round a stored mL amount to a clean display number in the chosen unit
export function displayAmount(ml: number, unit: Unit): number {
  if (unit === 'oz') return Math.round(mlToOz(ml) * 2) / 2; // nearest 0.5 oz
  return Math.round(ml); // nearest mL
}

function trim(n: number): string {
  return n % 1 === 0 ? String(n) : n.toFixed(1);
}

// "2 oz" / "2.5 oz" / "60 ml"
export function formatAmount(ml: number, unit: Unit): string {
  const v = displayAmount(ml, unit);
  return unit === 'oz' ? `${trim(v)} oz` : `${v} ml`;
}

// convert a display-unit stepper value back to canonical mL for storage
export function toMl(value: number, unit: Unit): number {
  return unit === 'oz' ? ozToMl(value) : value;
}
