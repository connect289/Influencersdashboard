"use client";
import { Command } from "cmdk";
import { Search } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Dialog as D } from "radix-ui";
import type { NavLink } from "./nav-links";
import { ICONS } from "./icons";

/** ⌘K / Ctrl+K: jump to any screen the person can use. Later phases add record search. */
export function CommandPalette({ links, labels }: { links: NavLink[]; labels: { open: string; placeholder: string; empty: string; title: string; shortcut: string } }) {
  const [open, setOpen] = useState(false);
  const router = useRouter();
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setOpen((v) => !v);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex h-10 w-full max-w-sm items-center gap-2 rounded-xl bg-surface-2 px-3 text-sm text-muted hover:text-ink"
        aria-label={labels.open}
      >
        <Search className="size-4" aria-hidden />
        <span className="flex-1 text-left">{labels.placeholder}</span>
        <kbd className="hidden rounded-md bg-surface px-1.5 py-0.5 text-xs md:inline">{labels.shortcut}</kbd>
      </button>
      <D.Root open={open} onOpenChange={setOpen}>
        <D.Portal>
          <D.Overlay className="fixed inset-0 z-40 bg-black/40" />
          <D.Content className="fixed top-[12vh] left-1/2 z-50 w-[92vw] max-w-lg -translate-x-1/2 overflow-hidden rounded-2xl bg-surface shadow-[var(--shadow-card)]">
            <D.Title className="sr-only">{labels.title}</D.Title>
            <D.Description className="sr-only">{labels.placeholder}</D.Description>
            <Command label={labels.title}>
              <Command.Input placeholder={labels.placeholder} className="h-12 w-full border-b border-line bg-transparent px-4 text-[15px] outline-none" />
              <Command.List className="max-h-80 overflow-y-auto p-2">
                <Command.Empty className="px-3 py-6 text-center text-sm text-muted">{labels.empty}</Command.Empty>
                {links.map((l) => {
                  const Icon = ICONS[l.icon];
                  return (
                    <Command.Item
                      key={l.href}
                      value={l.label}
                      onSelect={() => {
                        setOpen(false);
                        router.push(l.href);
                      }}
                      className="flex cursor-pointer items-center gap-3 rounded-xl px-3 py-2 text-sm data-[selected=true]:bg-surface-2"
                    >
                      <Icon className="size-4 text-muted" aria-hidden />
                      {l.label}
                    </Command.Item>
                  );
                })}
              </Command.List>
            </Command>
          </D.Content>
        </D.Portal>
      </D.Root>
    </>
  );
}
