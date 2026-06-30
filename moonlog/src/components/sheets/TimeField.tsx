import { TimePicker } from '../ui/TimePicker';

interface TimeFieldProps {
  value: number; // ms
  onChange: (ms: number) => void;
}

/**
 * "When did it happen?" field for the log sheets. A compact, brand-themed
 * picker that stays collapsed until tapped — no native scroll-wheel popping
 * open the moment the sheet appears.
 */
export function TimeField({ value, onChange }: TimeFieldProps) {
  return (
    <div className="sheet__field">
      <span className="field-label">Time</span>
      <TimePicker value={value} onChange={onChange} ariaLabel="time" />
    </div>
  );
}
