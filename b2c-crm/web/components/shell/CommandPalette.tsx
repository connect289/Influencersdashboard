"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowRight, Search, UserRound } from "lucide-react";
import { searchLeads, type LeadHit } from "@/app/search-actions";

export type PaletteEntry = { href: string; label: string; hint?: string };

/**
 * Search anywhere (spec B15, ⌘K): type a name, phone, email or application ID to jump to a lead, or the name of a
 * screen to open it. Ctrl/⌘+K or "/" opens it; the sidebar button too.
 */
export function CommandPalette({ pages, base }: { pages: PaletteEntry[]; base: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState("");
  const [leads, setLeads] = useState<LeadHit[]>([]);
  const [busy, setBusy] = useState(false);
  const [cursor, setCursor] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const seq = useRef(0);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const typing = (e.target as HTMLElement | null)?.closest("input, textarea, select, [contenteditable]");
      if ((e.key === "k" && (e.metaKey || e.ctrlKey)) || (e.key === "/" && !typing && !e.metaKey && !e.ctrlKey)) { e.preventDefault(); setOpen(true); }
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, []);
  useEffect(() => { if (open) { setQ(""); setLeads([]); setCursor(0); setTimeout(() => input.current?.focus(), 10); } }, [open]);

  const look = useCallback((text: string) => {
    const mine = ++seq.current;
    if (text.trim().length < 2) { setLeads([]); setBusy(false); return; }
    setBusy(true);
    searchLeads(text).then((r) => { if (mine === seq.current) { setLeads(r.ok && r.data ? r.data : []); setBusy(false); } });
  }, []);
  useEffect(() => { const t = setTimeout(() => look(q), 180); return () => clearTimeout(t); }, [q, look]);

  const words = q.trim().toLowerCase();
  const pageHits = words ? pages.filter((p) => p.label.toLowerCase().includes(words) || (p.hint ?? "").toLowerCase().includes(words)).slice(0, 6) : pages.slice(0, 8);
  const items: { key: string; href: string; node: React.ReactNode }[] = [
    ...leads.map((l) => ({ key: `l${l.lead_id}`, href: `${base}/leads/${l.lead_id}`, node: (
      <><UserRound className="icon s" aria-hidden /><span className="grow"><b>{l.name ?? `Lead #${l.lead_id}`}</b> <span className="muted small">{[l.phone, l.course, l.stage].filter(Boolean).join(" · ")}{l.owner_name ? ` · ${l.owner_name}` : ""}</span></span></>
    ) })),
    ...pageHits.map((p) => ({ key: `p${p.href}`, href: p.href, node: <><ArrowRight className="icon s" aria-hidden /><span className="grow">{p.label}{p.hint ? <span className="muted small"> · {p.hint}</span> : null}</span></> })),
  ];
  const go = (href: string) => { setOpen(false); router.push(href); };

  return (
    <>
      <button type="button" className="cmdk" onClick={() => setOpen(true)} aria-label="Search anywhere">
        <Search className="icon s" aria-hidden /> Search… <kbd>⌘K</kbd>
      </button>
      {open && (
        <div className="scrim center" onMouseDown={(e) => e.target === e.currentTarget && setOpen(false)}>
          <div className="sheet palette" role="dialog" aria-modal="true" aria-label="Search">
            <div className="search">
              <Search className="icon s" aria-hidden />
              <input ref={input} value={q} onChange={(e) => { setQ(e.target.value); setCursor(0); }} placeholder="A student's name, phone, email or application ID, or a screen"
                aria-label="Search" autoComplete="off"
                onKeyDown={(e) => {
                  if (e.key === "ArrowDown") { e.preventDefault(); setCursor((c) => Math.min(items.length - 1, c + 1)); }
                  if (e.key === "ArrowUp") { e.preventDefault(); setCursor((c) => Math.max(0, c - 1)); }
                  if (e.key === "Enter" && items[cursor]) go(items[cursor].href);
                }} />
              {busy && <span className="small muted">…</span>}
            </div>
            <div className="palette-list" role="listbox">
              {items.length === 0 && <p className="note" style={{ padding: "6px 4px" }}>{words.length >= 2 && !busy ? "Nothing found." : "Type to search."}</p>}
              {items.map((it, i) => (
                <button key={it.key} type="button" role="option" aria-selected={i === cursor} className="palette-item" onMouseEnter={() => setCursor(i)} onClick={() => go(it.href)}>{it.node}</button>
              ))}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
