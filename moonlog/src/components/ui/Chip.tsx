import type { ReactNode } from 'react';

interface ChipProps {
  selected: boolean;
  onClick: () => void;
  children: ReactNode;
}

export function Chip({ selected, onClick, children }: ChipProps) {
  return (
    <button
      type="button"
      className={`chip${selected ? ' is-selected' : ''}`}
      aria-pressed={selected}
      onClick={onClick}
    >
      {children}
    </button>
  );
}
