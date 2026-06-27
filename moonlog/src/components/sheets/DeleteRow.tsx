import { useEffect, useRef, useState } from 'react';

interface Props {
  label: string;
  onDelete: () => void | Promise<void>;
}

/** Two-tap inline delete confirm (spec: edit/delete "with confirm"). */
export function DeleteRow({ label, onDelete }: Props) {
  const [confirm, setConfirm] = useState(false);
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => () => { if (timer.current) window.clearTimeout(timer.current); }, []);

  const onClick = () => {
    if (!confirm) {
      setConfirm(true);
      timer.current = window.setTimeout(() => setConfirm(false), 3500);
      return;
    }
    if (timer.current) window.clearTimeout(timer.current);
    onDelete();
  };

  return (
    <button
      type="button"
      className="sheet__danger"
      onClick={onClick}
      aria-live="polite"
      aria-label={confirm ? `${label} — tap again to confirm` : label}
    >
      {confirm ? 'Tap again to delete' : label}
    </button>
  );
}
