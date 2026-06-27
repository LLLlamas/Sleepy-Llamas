import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react';

interface SheetProps {
  title: string;
  onClose: () => void;
  children: ReactNode;
  /** primary save button (sticky at the bottom) */
  onSave?: () => void;
  saveLabel?: string;
  saveDisabled?: boolean;
}

/**
 * Bottom sheet that slides up from the thumb zone. Closes on backdrop tap,
 * Esc, and swipe-down. Locks body scroll and restores focus on close.
 */
export function Sheet({ title, onClose, children, onSave, saveLabel = 'Save', saveDisabled }: SheetProps) {
  const sheetRef = useRef<HTMLDivElement>(null);
  const restoreFocus = useRef<HTMLElement | null>(null);
  const [dragY, setDragY] = useState(0);
  const dragStart = useRef<number | null>(null);

  useEffect(() => {
    restoreFocus.current = document.activeElement as HTMLElement | null;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    // focus first focusable element inside the sheet, else the sheet itself
    const focusable = sheetRef.current?.querySelector<HTMLElement>(
      'input, textarea, button, [tabindex]:not([tabindex="-1"])',
    );
    (focusable ?? sheetRef.current)?.focus();

    return () => {
      document.body.style.overflow = prevOverflow;
      restoreFocus.current?.focus?.();
    };
  }, []);

  const onKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onClose();
        return;
      }
      if (e.key === 'Tab') {
        // trap focus so the aria-modal contract holds (background is unreachable)
        const focusables = sheetRef.current?.querySelectorAll<HTMLElement>(
          'input, textarea, select, button, [href], [tabindex]:not([tabindex="-1"])',
        );
        if (!focusables || focusables.length === 0) return;
        const list = [...focusables].filter((el) => !el.hasAttribute('disabled'));
        const first = list[0];
        const last = list[list.length - 1];
        const active = document.activeElement;
        if (e.shiftKey && active === first) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && active === last) {
          e.preventDefault();
          first.focus();
        }
      }
    },
    [onClose],
  );

  // lightweight swipe-down-to-close on the grip / header area
  const onTouchStart = (e: React.TouchEvent) => {
    dragStart.current = e.touches[0].clientY;
  };
  const onTouchMove = (e: React.TouchEvent) => {
    if (dragStart.current == null) return;
    const dy = e.touches[0].clientY - dragStart.current;
    if (dy > 0) setDragY(dy);
  };
  const onTouchEnd = () => {
    if (dragY > 90) onClose();
    setDragY(0);
    dragStart.current = null;
  };

  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div
        className="sheet"
        ref={sheetRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
        onKeyDown={onKeyDown}
        style={dragY ? { transform: `translateY(${dragY}px)`, transition: 'none' } : undefined}
      >
        <div
          className="sheet__grip-zone"
          onTouchStart={onTouchStart}
          onTouchMove={onTouchMove}
          onTouchEnd={onTouchEnd}
        >
          <div className="sheet__grip" />
        </div>
        <h2 className="sheet__title">{title}</h2>
        {children}
        {onSave && (
          <button
            type="button"
            className="sheet__save"
            onClick={onSave}
            disabled={saveDisabled}
          >
            {saveLabel}
          </button>
        )}
      </div>
    </div>
  );
}
