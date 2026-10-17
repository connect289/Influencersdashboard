"use client";

import { Drawer } from "vaul";
import { cn } from "@/lib/utils";

/** Mobile bottom sheet (filters on phones, spec 6.3) with a drag handle and a sticky footer for Apply + live count. */
export function BottomSheet({
  open,
  onOpenChange,
  title,
  children,
  footer,
  className,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  title: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
  className?: string;
}) {
  return (
    <Drawer.Root open={open} onOpenChange={onOpenChange}>
      <Drawer.Portal>
        <Drawer.Overlay className="fixed inset-0 z-[var(--z-overlay)] bg-[rgb(2_6_13/0.55)]" />
        <Drawer.Content
          className={cn(
            "glass-strong fixed inset-x-0 bottom-0 z-[var(--z-panel)] flex max-h-[88dvh] flex-col rounded-t-[var(--radius-2xl)] outline-none",
            className,
          )}
        >
          <div aria-hidden className="bg-border-strong mx-auto mt-2.5 h-1.5 w-12 rounded-full" />
          <Drawer.Title className="font-display px-5 pt-3 pb-2 text-lg font-semibold">{title}</Drawer.Title>
          <Drawer.Description className="sr-only">{title}</Drawer.Description>
          <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pb-4">{children}</div>
          {footer ? (
            <div className="border-border border-t px-5 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
              {footer}
            </div>
          ) : null}
        </Drawer.Content>
      </Drawer.Portal>
    </Drawer.Root>
  );
}
