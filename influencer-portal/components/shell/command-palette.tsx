"use client";
import { Command } from "cmdk";
import { Search, UserRound } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { searchCreators } from "@/lib/actions/creators";
import { Dialog as D } from "radix-ui";
import type { NavLink } from "./nav-links";
import { ICONS } from "./icons";

interface Hit {
  id: string;
  name: string;
  handle: string;
}

/** ⌘K / Ctrl+K: jump to any screen the person can use, or to a creator by name or handle. */
export function CommandPalette({
  links,
  labels,
  searchCreatorsEnabled = false,
}: {
  links: NavLink[];
  labels: {
    open: string;
    placeholder: string;
    empty: string;
    title: string;
    shortcut: string;
    creators: string;
  };
  searchCreatorsEnabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [hits, setHits] = useState<Hit[]>([]);
  const router = useRouter();
  const searching = searchCreatorsEnabled && query.trim().length >= 2;
  useEffect(() => {
    if (!searching) return;
    let live = true;
    const id = setTimeout(() => {
      void searchCreators(query).then((r) => {
        if (live) setHits(r);
      });
    }, 250);
    return () => {
      live = false;
      clearTimeout(id);
    };
  }, [query, searching]);
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
              <Command.Input
                value={query}
                onValueChange={setQuery}
                placeholder={labels.placeholder}
                className="h-12 w-full border-b border-line bg-transparent px-4 text-[15px] outline-none"
              />
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
                {searching && hits.length ? (
                  <Command.Group
                    heading={labels.creators}
                    className="mt-1 text-xs text-muted [&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:py-1"
                  >
                    {hits.map((h) => (
                      <Command.Item
                        key={h.id}
                        value={`creator ${h.name} ${h.handle} ${h.id}`}
                        onSelect={() => {
                          setOpen(false);
                          router.push(`/admin/creators/${h.id}`);
                        }}
                        className="flex cursor-pointer items-center gap-3 rounded-xl px-3 py-2 text-sm text-ink data-[selected=true]:bg-surface-2"
                      >
                        <UserRound className="size-4 text-muted" aria-hidden />
                        <span>{h.name}</span>
                        <span className="text-xs text-muted">@{h.handle}</span>
                      </Command.Item>
                    ))}
                  </Command.Group>
                ) : null}
              </Command.List>
            </Command>
          </D.Content>
        </D.Portal>
      </D.Root>
    </>
  );
}
