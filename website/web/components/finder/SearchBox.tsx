"use client";

import { useRouter } from "next/navigation";
import { useEffect, useId, useMemo, useRef, useState } from "react";
import { ArrowUpRight, GraduationCap, Layers, Loader2, Search, University } from "lucide-react";
import { track } from "@/lib/client/analytics";
import type { Suggestions } from "@/lib/search/types";
import { cn } from "@/lib/utils";

type Item =
  | { kind: "programme"; id: string; label: string; meta: string; href: string }
  | { kind: "group"; id: string; label: string; meta: string; href: string }
  | { kind: "university"; id: string; label: string; meta: string; href: string }
  | { kind: "query"; id: string; label: string; meta: string };

const cache = new Map<string, Suggestions>();

/**
 * Search box with instant suggestions grouped as Programmes · Specialisations · Universities (spec 6.1). WAI-ARIA
 * combobox: arrow keys move, Enter picks, Escape closes. Free text is turned into structured filters by the server
 * (deterministic parsing + synonyms), then the finder opens with those filters as chips.
 */
export function SearchBox({
  initialQuery = "",
  size = "bar",
  basePath = "/programmes",
  placeholder = "Search, e.g. “mba under 2 lakh”",
  autoFocus,
  className,
}: {
  initialQuery?: string;
  size?: "bar" | "hero";
  basePath?: string;
  placeholder?: string;
  autoFocus?: boolean;
  className?: string;
}) {
  const router = useRouter();
  const id = useId();
  const listId = `${id}-list`;
  const [value, setValue] = useState(initialQuery);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const [fetched, setFetched] = useState<{ q: string; s: Suggestions } | null>(null);
  const [busy, setBusy] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const qNorm = value.trim().toLowerCase();
  const data = qNorm.length < 2 ? null : (cache.get(qNorm) ?? (fetched?.q === qNorm ? fetched.s : null));

  useEffect(() => {
    if (qNorm.length < 2 || cache.has(qNorm)) return;
    const ctrl = new AbortController();
    const t = setTimeout(async () => {
      try {
        const res = await fetch(`/api/suggest?q=${encodeURIComponent(qNorm)}`, { signal: ctrl.signal });
        if (!res.ok) return;
        const j = (await res.json()) as Suggestions;
        cache.set(qNorm, j);
        setFetched({ q: qNorm, s: j });
      } catch {
        // aborted or offline: keep the box usable without suggestions
      }
    }, 120);
    return () => {
      clearTimeout(t);
      ctrl.abort();
    };
  }, [qNorm]);

  const items = useMemo<Item[]>(() => {
    const out: Item[] = [];
    for (const p of data?.programmes ?? []) {
      out.push({ kind: "programme", id: `p-${p.id}`, label: p.label, meta: `${p.full} · ${p.universities} universities`, href: `${basePath}?programme=${p.id}` });
    }
    for (const g of data?.groups ?? []) {
      out.push({ kind: "group", id: `g-${g.key}`, label: g.label, meta: `${g.universities} ${g.universities === 1 ? "university" : "universities"}`,
        href: `${basePath}?programme=${g.programme_id}&spec=${g.spec_ids.join(",")}` });
    }
    for (const u of data?.universities ?? []) {
      out.push({ kind: "university", id: `u-${u.slug}`, label: u.label, meta: `${u.count} programmes`, href: `${basePath}?uni=${u.slug}` });
    }
    if (value.trim()) out.push({ kind: "query", id: "q", label: `Search for “${value.trim()}”`, meta: "Use all words" });
    return out;
  }, [data, value, basePath]);

  async function submit(text: string) {
    const q = text.trim();
    if (!q) return router.push(basePath);
    setBusy(true);
    try {
      const res = await fetch(`/api/search/resolve?q=${encodeURIComponent(q)}`);
      const j = res.ok ? ((await res.json()) as { qs: string; parsed: number }) : { qs: `q=${encodeURIComponent(q)}`, parsed: 0 };
      track("search", { query_length: q.length, parsed_filters: j.parsed });
      router.push(j.qs ? `${basePath}?${j.qs}` : basePath);
    } finally {
      setBusy(false);
      setOpen(false);
    }
  }

  function choose(item: Item) {
    setOpen(false);
    if (item.kind === "query") return void submit(value);
    track("search", { query_length: value.trim().length, parsed_filters: 1 });
    router.push(item.href);
  }

  function onKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setOpen(true);
      setActive((a) => Math.min(items.length - 1, a + 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((a) => Math.max(-1, a - 1));
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (open && active >= 0 && items[active]) choose(items[active]!);
      else void submit(value);
    } else if (e.key === "Escape") {
      setOpen(false);
      setActive(-1);
    }
  }

  const groups: { kind: Item["kind"]; title: string; icon: React.ReactNode }[] = [
    { kind: "programme", title: "Programmes", icon: <GraduationCap className="size-4" aria-hidden /> },
    { kind: "group", title: "Specialisations", icon: <Layers className="size-4" aria-hidden /> },
    { kind: "university", title: "Universities", icon: <University className="size-4" aria-hidden /> },
    { kind: "query", title: "Search", icon: <Search className="size-4" aria-hidden /> },
  ];
  const showList = open && items.length > 0 && value.trim().length >= 2;

  return (
    <div className={cn("relative", className)}>
      <form
        role="search"
        onSubmit={(e) => {
          e.preventDefault();
          void submit(value);
        }}
        className={cn(
          "glass hairline-lumen flex items-center gap-3 rounded-full px-5 focus-within:shadow-[var(--glow-amber)]",
          size === "hero" ? "h-16" : "h-14",
        )}
      >
        {busy ? <Loader2 className="text-subtle size-5 animate-spin" aria-hidden /> : <Search className="text-subtle size-5" aria-hidden />}
        <label htmlFor={`${id}-input`} className="sr-only">
          Search programmes, specialisations or universities
        </label>
        <input
          ref={inputRef}
          id={`${id}-input`}
          type="search"
          role="combobox"
          aria-autocomplete="list"
          aria-expanded={showList}
          aria-controls={listId}
          aria-activedescendant={showList && active >= 0 ? `${id}-${items[active]?.id}` : undefined}
          autoComplete="off"
          enterKeyHint="search"
          autoFocus={autoFocus}
          value={value}
          placeholder={placeholder}
          onChange={(e) => {
            setValue(e.target.value);
            setOpen(true);
            setActive(-1);
          }}
          onFocus={() => setOpen(true)}
          onBlur={() => setTimeout(() => setOpen(false), 120)}
          onKeyDown={onKeyDown}
          className="text-text placeholder:text-subtle h-full min-w-0 flex-1 bg-transparent text-base outline-none [&::-webkit-search-cancel-button]:hidden"
        />
        <button type="submit" className="bg-primary text-on-primary hidden h-10 shrink-0 items-center rounded-full px-4 text-sm font-semibold sm:inline-flex">
          Search
        </button>
      </form>
      <div
        id={listId}
        role="listbox"
        aria-label="Suggestions"
        hidden={!showList}
        className="glass-strong absolute inset-x-0 top-[calc(100%+0.5rem)] z-[var(--z-popover)] max-h-[60vh] overflow-y-auto rounded-[var(--radius-xl)] p-2"
      >
        {groups.map((g) => {
          const list = items.map((it, i) => ({ it, i })).filter(({ it }) => it.kind === g.kind);
          if (!list.length) return null;
          return (
            <div key={g.kind} role="group" aria-labelledby={`${id}-g-${g.kind}`} className="py-1">
              <div id={`${id}-g-${g.kind}`} className="eyebrow flex items-center gap-2 px-3 py-1.5">
                {g.icon}
                {g.title}
              </div>
              {list.map(({ it, i }) => (
                <div
                  key={it.id}
                  id={`${id}-${it.id}`}
                  role="option"
                  aria-selected={i === active}
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => choose(it)}
                  onMouseEnter={() => setActive(i)}
                  className={cn(
                    "flex cursor-pointer items-center justify-between gap-3 rounded-[var(--radius-md)] px-3 py-2.5",
                    i === active ? "bg-surface-hover" : "",
                  )}
                >
                  <span className="min-w-0">
                    <span className="text-text block truncate font-medium">{it.label}</span>
                    <span className="text-subtle block truncate text-xs">{it.meta}</span>
                  </span>
                  <ArrowUpRight className="text-subtle size-4 shrink-0" aria-hidden />
                </div>
              ))}
            </div>
          );
        })}
      </div>
    </div>
  );
}
