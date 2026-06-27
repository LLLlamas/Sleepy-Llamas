interface SwatchProps {
  color: string;
  name: string;
  selected: boolean;
  onClick: () => void;
}

export function Swatch({ color, name, selected, onClick }: SwatchProps) {
  return (
    <button
      type="button"
      className={`swatch${selected ? ' is-selected' : ''}`}
      aria-pressed={selected}
      aria-label={name}
      onClick={onClick}
    >
      <span className="swatch__dot" style={{ background: color }} />
      <span className="swatch__name">{name}</span>
    </button>
  );
}
