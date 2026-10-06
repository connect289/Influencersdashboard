"use client";
import { useEffect, useId, useRef, useState } from "react";
import { LoaderCircle } from "lucide-react";
import { Button } from "./Button";

/**
 * Confirmation with an optional required reason. A native <dialog>: focus trap, Escape and top layer for free.
 * `onConfirm` returns an error message to show, or nothing on success (the dialog then closes).
 */
export function ConfirmDialog({ open, onClose, title, children, confirmLabel, tone = "primary", reason, onConfirm }: {
  open: boolean;
  onClose: () => void;
  title: string;
  children?: React.ReactNode;
  confirmLabel: string;
  tone?: "primary" | "danger";
  reason?: { label: string; placeholder?: string };
  onConfirm: (reason: string) => Promise<string | void>;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const id = useId();
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) { setText(""); setError(null); d.showModal(); }
    if (!open && d.open) d.close();
  }, [open]);

  const confirm = async () => {
    if (reason && !text.trim()) { setError("A reason is required."); return; }
    setPending(true);
    try {
      const err = await onConfirm(text.trim());
      if (err) setError(err); else onClose();
    } catch {
      setError("Something went wrong. Try again.");
    } finally {
      setPending(false);
    }
  };

  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onClick={(e) => { if (e.target === ref.current && !pending) onClose(); }}
      aria-labelledby={`${id}-title`}
      className="m-auto w-[min(460px,calc(100vw-2rem))] rounded-[var(--radius-card)] border border-border bg-surface p-0 text-fg shadow-2xl backdrop:bg-overlay backdrop:backdrop-blur-sm"
    >
      <div className="p-5">
        <h2 id={`${id}-title`} className="text-[15px] font-semibold">{title}</h2>
        {children && <div className="mt-1.5 text-[13px] leading-5 text-muted">{children}</div>}
        {reason && (
          <div className="mt-4 space-y-1.5">
            <label htmlFor={`${id}-reason`} className="text-[13px] font-medium">{reason.label}</label>
            <textarea
              id={`${id}-reason`}
              value={text}
              maxLength={500}
              rows={3}
              onChange={(e) => setText(e.target.value)}
              placeholder={reason.placeholder}
              className="w-full resize-none rounded-lg border border-border bg-surface px-3 py-2 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
            />
          </div>
        )}
        {error && <p role="alert" className="mt-3 text-[13px] text-danger">{error}</p>}
      </div>
      <div className="flex justify-end gap-2 border-t border-border bg-surface-2/60 px-5 py-3">
        <Button variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button>
        <Button variant={tone} size="sm" onClick={confirm} disabled={pending} aria-busy={pending}>
          {pending && <LoaderCircle className="size-3.5 animate-spin" />} {confirmLabel}
        </Button>
      </div>
    </dialog>
  );
}
