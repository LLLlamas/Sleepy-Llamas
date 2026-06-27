export type TabId = 'tonight' | 'summary' | 'settings';

const TABS: { id: TabId; label: string; icon: string }[] = [
  { id: 'tonight', label: 'Tonight', icon: '🌙' },
  { id: 'summary', label: 'Summary', icon: '📋' },
  { id: 'settings', label: 'Settings', icon: '⚙️' },
];

interface Props {
  active: TabId;
  onChange: (id: TabId) => void;
}

export function TabBar({ active, onChange }: Props) {
  return (
    <nav className="tabbar" aria-label="Primary">
      {TABS.map((t) => (
        <button
          key={t.id}
          type="button"
          className={`tab${active === t.id ? ' is-active' : ''}`}
          aria-current={active === t.id ? 'page' : undefined}
          onClick={() => onChange(t.id)}
        >
          <span className="tab__icon" aria-hidden="true">{t.icon}</span>
          {t.label}
        </button>
      ))}
    </nav>
  );
}
