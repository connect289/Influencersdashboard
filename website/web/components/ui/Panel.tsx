"use client";

import { useRef } from "react";
import { Dialog } from "radix-ui";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Detail panel (spec 6.6): right-side drawer on desktop, full-screen sheet on mobile. Focus is trapped while open and
 * returned to the trigger on close; Escape closes; the page behind is inert for screen readers.
 */
export function Panel({
  open,
  onOpenChange,
  title,
  description,
  children,
  footer,
  className,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  title: React.ReactNode;
  description?: React.ReactNode;
  children: React.ReactNode;
  footer?: React.ReactNode;
  className?: string;
}) {
  // Panels open from links that change the URL (deep links), not from a Radix trigger, so remember what had focus when
  // the panel opened and give it back on close (or the same link, if the list re-rendered meanwhile).
  const returnTo = useRef<{ el: HTMLElement | null; href: string | null }>({ el: null, href: null });
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="panel-overlay fixed inset-0 z-[var(--z-overlay)] bg-[rgb(2_6_13/0.55)] backdrop-blur-[3px]" />
        <Dialog.Content
          onOpenAutoFocus={() => {
            const el = document.activeElement instanceof HTMLElement && document.activeElement !== document.body ? document.activeElement : null;
            returnTo.current = { el, href: el?.getAttribute("href") ?? null };
          }}
          onCloseAutoFocus={(e) => {
            const { el, href } = returnTo.current;
            const target = el?.isConnected ? el : href ? document.querySelector<HTMLElement>(`a[href="${CSS.escape(href)}"]`) : null;
            if (target) {
              e.preventDefault();
              target.focus({ preventScroll: true });
            }
          }}
          className={cn(
            "panel-content glass-strong fixed inset-0 z-[var(--z-panel)] flex flex-col outline-none md:inset-y-3 md:right-3 md:left-auto md:w-[min(600px,calc(100vw-1.5rem))] md:rounded-[var(--radius-2xl)]",
            className,
          )}
        >
          <header className="border-border flex items-start gap-3 border-b px-5 py-4 md:px-6">
            <div className="min-w-0 flex-1">
              <Dialog.Title className="font-display text-text text-xl leading-snug font-semibold">{title}</Dialog.Title>
              {description ? (
                <Dialog.Description className="text-muted mt-0.5 text-sm">{description}</Dialog.Description>
              ) : (
                <Dialog.Description className="sr-only">Details</Dialog.Description>
              )}
            </div>
            <Dialog.Close
              className="border-border text-muted hover:bg-surface-hover hover:text-text grid size-10 shrink-0 place-items-center rounded-full border"
              aria-label="Close"
            >
              <X className="size-5" aria-hidden />
            </Dialog.Close>
          </header>
          <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 py-5 md:px-6">{children}</div>
          {footer ? (
            <footer className="border-border border-t px-5 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] md:px-6">
              {footer}
            </footer>
          ) : null}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
