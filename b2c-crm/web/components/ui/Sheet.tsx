"use client";
import { useEffect, useRef } from "react";
import { X } from "lucide-react";

/** Bottom sheet on a phone, centred dialog on a desktop. Escape or the scrim closes it; focus moves inside. */
export function Sheet({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const prev = document.activeElement as HTMLElement | null;
    ref.current?.querySelector<HTMLElement>("input, select, textarea, button:not([data-close])")?.focus();
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("keydown", onKey);
      prev?.focus();
    };
  }, [onClose]);
  return (
    <div className="scrim sheet-on-desk" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="sheet" role="dialog" aria-modal="true" aria-label={title} ref={ref}>
        <div className="grab" aria-hidden />
        <div className="head">
          <h2>{title}</h2>
          <button type="button" className="btn quiet sm" onClick={onClose} aria-label="Close" data-close>
            <X className="icon s" aria-hidden />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}
