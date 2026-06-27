import { Stepper } from '../ui/Stepper';
import { fmtClockShort } from '../../lib/time';

const STEP_MIN = 5;

interface TimeFieldProps {
  value: number; // ms
  onChange: (ms: number) => void;
}

function hint(ms: number): string {
  const deltaMin = Math.round((Date.now() - ms) / 60000);
  if (deltaMin === 0) return 'now';
  if (deltaMin > 0) return `${deltaMin} min ago`;
  return `in ${-deltaMin} min`;
}

/** Time picker tuned for "it happened a few minutes ago": −5 / +5 steppers. */
export function TimeField({ value, onChange }: TimeFieldProps) {
  return (
    <div className="sheet__field">
      <span className="field-label">Time</span>
      <Stepper
        ariaLabel="adjust time"
        decLabel="−5"
        incLabel="+5"
        onDec={() => onChange(value - STEP_MIN * 60000)}
        onInc={() => onChange(Math.min(Date.now(), value + STEP_MIN * 60000))}
        incDisabled={value >= Date.now()}
      >
        {fmtClockShort(value)} <small>{hint(value)}</small>
      </Stepper>
    </div>
  );
}
