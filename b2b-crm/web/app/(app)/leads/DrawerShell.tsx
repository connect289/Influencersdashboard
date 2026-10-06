"use client";
import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { X } from "lucide-react";
import { cn } from "@/components/ui/cn";

export type DrawerTab = { id: string; label: string; count?: number; content: React.ReactNode };

/** Right-hand panel for one lead. The URL (?lead=) opens it; closing navigates back to the list, keeping filters. */
export function DrawerShell({ closeHref, label, header, tabs }: { closeHref: string; label: string; header: React.ReactNode; tabs: DrawerTab[] }) {
  const router = useRouter();
  const panel = useRef<HTMLDivElement>(null);
  const [tab, setTab] = useState(tabs[0]?.id);
  const close = () => router.push(closeHref, { scroll: false });

  useEffect(() => {
    panel.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      // Leave Escape to an open dialog (it closes itself first).
      if (e.key === "Escape" && !document.querySelector("dialog[open]")) router.push(closeHref, { scroll: false });
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [router, closeHref]);

  const active = tabs.find((t) => t.id === tab) ?? tabs[0];

  return (
    <div className="fixed inset-0 z-40" role="dialog" aria-modal="true" aria-label={label}>
      <button type="button" aria-label="Close" tabIndex={-1} className="absolute inset-0 bg-overlay animate-fade-in" onClick={close} />
      <div
        ref={panel}
        tabIndex={-1}
        className="absolute inset-y-0 right-0 flex w-full max-w-[600px] flex-col border-l border-border bg-surface shadow-2xl outline-none animate-drawer-in"
      >
        <div className="relative border-b border-border px-5 pb-0 pt-4">
          <button type="button" aria-label="Close lead" onClick={close} className="absolute right-3 top-3 grid size-8 place-items-center rounded-lg text-muted hover:bg-surface-hover hover:text-fg">
            <X className="size-4" />
          </button>
          {header}
          {tabs.length > 1 && (
            <div role="tablist" aria-label="Lead sections" className="-mb-px mt-4 flex gap-4">
              {tabs.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  role="tab"
                  id={`tab-${t.id}`}
                  aria-selected={t.id === active?.id}
                  aria-controls={`panel-${t.id}`}
                  onClick={() => setTab(t.id)}
                  className={cn(
                    "border-b-2 pb-2.5 text-[13px] font-medium transition-colors",
                    t.id === active?.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg",
                  )}
                >
                  {t.label}
                  {t.count !== undefined && <span className="tabular ml-1.5 text-[11px] text-subtle">{t.count}</span>}
                </button>
              ))}
            </div>
          )}
        </div>
        {active && (
          <div role="tabpanel" id={`panel-${active.id}`} aria-labelledby={`tab-${active.id}`} className="min-h-0 flex-1 overflow-y-auto">
            {active.content}
          </div>
        )}
      </div>
    </div>
  );
}
