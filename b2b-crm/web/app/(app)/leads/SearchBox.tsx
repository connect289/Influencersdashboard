"use client";
import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { LoaderCircle, Search, X } from "lucide-react";

/** Name, email, phone (4+ digits) or lead id. Updates the URL 300 ms after typing stops; `/` focuses it. */
export function SearchBox({ initial, search }: { initial: string; search: string }) {
  const router = useRouter();
  const [value, setValue] = useState(initial);
  const [pending, start] = useTransition();
  const input = useRef<HTMLInputElement>(null);
  // Follow the URL when it changes from elsewhere (e.g. "Clear filters"), without eating a trailing space mid-typing.
  const [seen, setSeen] = useState(initial);
  if (initial !== seen) {
    setSeen(initial);
    if (initial !== value.trim()) setValue(initial);
  }

  useEffect(() => {
    const p = new URLSearchParams(search);
    if (value.trim() === (p.get("q") ?? "")) return;
    const t = setTimeout(() => {
      if (value.trim()) p.set("q", value.trim()); else p.delete("q");
      const s = p.toString();
      start(() => router.replace(`/leads${s ? `?${s}` : ""}`, { scroll: false }));
    }, 300);
    return () => clearTimeout(t);
  }, [value, search, router]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null;
      if (e.key !== "/" || e.metaKey || e.ctrlKey || t?.closest("input, textarea, select, [contenteditable=true]")) return;
      e.preventDefault();
      input.current?.focus();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  return (
    <div className="relative min-w-0 flex-1 basis-64 sm:max-w-sm">
      <label htmlFor="lead-search" className="sr-only">Search leads</label>
      {pending
        ? <LoaderCircle className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 animate-spin text-subtle" aria-hidden />
        : <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-subtle" aria-hidden />}
      <input
        ref={input}
        id="lead-search"
        type="search"
        value={value}
        maxLength={100}
        autoComplete="off"
        spellCheck={false}
        onChange={(e) => setValue(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Escape" && value) { e.preventDefault(); setValue(""); } }}
        placeholder="Name, phone, email or ID"
        className="h-9 w-full rounded-lg border border-border bg-surface pl-9 pr-8 text-[13px] text-fg placeholder:text-subtle transition-colors hover:border-border-strong focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 [&::-webkit-search-cancel-button]:hidden"
      />
      {value && (
        <button type="button" aria-label="Clear search" onClick={() => setValue("")} className="absolute right-1.5 top-1/2 grid size-6 -translate-y-1/2 place-items-center rounded-md text-subtle hover:bg-surface-hover hover:text-fg">
          <X className="size-3.5" />
        </button>
      )}
    </div>
  );
}
