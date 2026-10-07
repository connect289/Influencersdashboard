"use client";
import { useEffect, useRef } from "react";
import { LoaderCircle } from "lucide-react";
import { Button } from "./Button";

export const fieldBase = "h-9 rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger disabled:bg-surface-2 disabled:text-subtle";
export const field = `${fieldBase} w-full`;
export const area = "w-full rounded-lg border border-border bg-surface px-3 py-2 font-mono text-[12px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";

/** A native <dialog> form shell: title, body, error line, Cancel and a primary action. */
export function Modal({ open, onClose, title, children, error, pending, onSubmit, submitLabel = "Save", wide }: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
  error?: string | null;
  pending?: boolean;
  onSubmit?: () => void;
  submitLabel?: string;
  wide?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
  }, [open]);
  return (
    <dialog ref={ref} onClose={onClose} aria-label={title}
      className={`m-auto ${wide ? "w-[min(760px,calc(100vw-2rem))]" : "w-[min(560px,calc(100vw-2rem))]"} rounded-[var(--radius-card)] border border-border bg-surface p-0 text-fg shadow-2xl backdrop:bg-overlay backdrop:backdrop-blur-sm`}>
      <form onSubmit={(e) => { e.preventDefault(); onSubmit?.(); }} noValidate>
        <div className="max-h-[75vh] space-y-4 overflow-y-auto p-5">
          <h2 className="text-[15px] font-semibold">{title}</h2>
          {children}
          {error && <p role="alert" className="text-[13px] text-danger">{error}</p>}
        </div>
        <div className="flex justify-end gap-2 border-t border-border bg-surface-2/60 px-5 py-3">
          <Button variant="secondary" size="sm" onClick={onClose} disabled={pending}>{onSubmit ? "Cancel" : "Close"}</Button>
          {onSubmit && <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} {submitLabel}</Button>}
        </div>
      </form>
    </dialog>
  );
}

export function Label({ text, hint, children }: { text: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-[13px] font-medium">{text}</span>
      {children}
      {hint && <span className="block text-[11.5px] text-subtle">{hint}</span>}
    </label>
  );
}
