import { Sheet } from './Sheet';

interface Props {
  title: string;
  message: string;
  confirmLabel: string;
  onConfirm: () => void;
  onCancel: () => void;
  danger?: boolean;
}

/** A clear, two-button confirmation (Cancel / Confirm) in a bottom sheet. */
export function ConfirmDialog({ title, message, confirmLabel, onConfirm, onCancel, danger }: Props) {
  return (
    <Sheet title={title} onClose={onCancel}>
      <p className="confirm-msg">{message}</p>
      <div className="confirm-actions">
        <button type="button" className="btn btn--ghost" onClick={onCancel}>
          Cancel
        </button>
        <button
          type="button"
          className={`btn ${danger ? 'btn--danger' : 'btn--primary'}`}
          onClick={onConfirm}
        >
          {confirmLabel}
        </button>
      </div>
    </Sheet>
  );
}
