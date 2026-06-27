import type { ReactNode } from 'react';

interface StepperProps {
  onDec: () => void;
  onInc: () => void;
  children: ReactNode; // the formatted value display
  decDisabled?: boolean;
  incDisabled?: boolean;
  decLabel?: string;
  incLabel?: string;
  ariaLabel?: string;
}

export function Stepper({
  onDec,
  onInc,
  children,
  decDisabled,
  incDisabled,
  decLabel = '−',
  incLabel = '+',
  ariaLabel,
}: StepperProps) {
  return (
    <div className="stepper" role="group" aria-label={ariaLabel}>
      <button
        type="button"
        className="stepper__btn"
        onClick={onDec}
        disabled={decDisabled}
        aria-label="decrease"
      >
        {decLabel}
      </button>
      <div className="stepper__value tabular">{children}</div>
      <button
        type="button"
        className="stepper__btn"
        onClick={onInc}
        disabled={incDisabled}
        aria-label="increase"
      >
        {incLabel}
      </button>
    </div>
  );
}
