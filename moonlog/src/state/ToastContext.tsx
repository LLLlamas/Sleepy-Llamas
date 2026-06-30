import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { buzz } from '../lib/haptics';

interface ToastOptions {
  undo?: () => void | Promise<void>;
  durationMs?: number;
}
interface ToastState {
  id: number;
  message: string;
  undo?: () => void | Promise<void>;
}

interface Ctx {
  showToast: (message: string, opts?: ToastOptions) => void;
}

const ToastCtx = createContext<Ctx | null>(null);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<ToastState | null>(null);
  const timer = useRef<number | undefined>(undefined);
  const seq = useRef(0);

  const clear = useCallback(() => {
    if (timer.current) window.clearTimeout(timer.current);
    setToast(null);
  }, []);

  const showToast = useCallback((message: string, opts?: ToastOptions) => {
    if (timer.current) window.clearTimeout(timer.current);
    const id = ++seq.current;
    setToast({ id, message, undo: opts?.undo });
    const duration = opts?.durationMs ?? (opts?.undo ? 1800 : 1000);
    timer.current = window.setTimeout(() => {
      // only clear if this is still the active toast
      setToast((t) => (t && t.id === id ? null : t));
    }, duration);
  }, []);

  useEffect(() => () => { if (timer.current) window.clearTimeout(timer.current); }, []);

  const onUndo = useCallback(async () => {
    const action = toast?.undo;
    clear();
    if (action) {
      buzz(15);
      await action();
    }
  }, [toast, clear]);

  return (
    <ToastCtx.Provider value={{ showToast }}>
      {children}
      {toast && (
        <div className="toast-wrap" role="status" aria-live="polite">
          <div className="toast">
            <span className="toast__msg">{toast.message}</span>
            {toast.undo && (
              <button type="button" className="toast__undo" onClick={onUndo}>
                Undo
              </button>
            )}
          </div>
        </div>
      )}
    </ToastCtx.Provider>
  );
}

export function useToast(): Ctx {
  const ctx = useContext(ToastCtx);
  if (!ctx) throw new Error('useToast must be used within ToastProvider');
  return ctx;
}
