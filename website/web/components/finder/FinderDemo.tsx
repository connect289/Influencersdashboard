"use client";

import { startTransition, useDeferredValue, useMemo, useState } from "react";
import { GitCompareArrows, Search, SlidersHorizontal, Sparkles } from "lucide-react";
import { BottomSheet } from "@/components/ui/BottomSheet";
import { Button } from "@/components/ui/Button";
import { Chip } from "@/components/ui/Chip";
import { EmptyState } from "@/components/ui/DataViz";
import { Odometer } from "@/components/ui/Odometer";
import { Panel } from "@/components/ui/Panel";
import { FilterPopover } from "@/components/ui/Popover";
import { RangeSlider } from "@/components/ui/RangeSlider";
import { Segmented } from "@/components/ui/Segmented";
import { formatInrCompact } from "@/lib/format";
import { groupOfferings, type SeedOffering } from "@/lib/seed/concept";
import { cn } from "@/lib/utils";
import { GroupCard } from "./GroupCard";
import { OfferingDetail } from "./OfferingDetail";
import { OfferingRow } from "./OfferingRow";

const NAAC = ["A++", "A+", "A"];

/**
 * Phase 1 concept finder over real seed data: search, live facet counts (zero-count options disabled, not hidden), fee
 * slider with histogram, grouped/flat results, applied-filter chips, mobile bottom sheet, detail panel, compare tray.
 * Concept "a" uses a left facet rail; concept "b" a horizontal filter bar. Phase 4 replaces the data layer with
 * web_search() and URL state.
 */
export function FinderDemo({ offerings, variant = "a" }: { offerings: SeedOffering[]; variant?: "a" | "b" }) {
  const feeMin = Math.min(...offerings.map((o) => o.feeTotal));
  const feeMax = Math.max(...offerings.map((o) => o.feeTotal));
  const [q, setQ] = useState("");
  const [level, setLevel] = useState<string | null>(null);
  const [programme, setProgramme] = useState<string | null>(null);
  const [naac, setNaac] = useState<string | null>(null);
  const [fee, setFee] = useState<[number, number]>([feeMin, feeMax]);
  const [view, setView] = useState<"grouped" | "flat">("grouped");
  const [open, setOpen] = useState<SeedOffering | null>(null);
  const [sheet, setSheet] = useState(false);
  const [shortlist, setShortlist] = useState<Set<number>>(new Set());
  const [compare, setCompare] = useState<Set<number>>(new Set());
  const dq = useDeferredValue(q);

  const matches = (o: SeedOffering, skip?: "level" | "programme" | "naac") => {
    const text = `${o.programme} ${o.specialisation} ${o.university} ${o.universityShort}`.toLowerCase();
    if (
      dq &&
      !dq
        .toLowerCase()
        .split(/\s+/)
        .every((t) => text.includes(t))
    )
      return false;
    if (skip !== "level" && level && o.level !== level) return false;
    if (skip !== "programme" && programme && o.programme !== programme) return false;
    if (skip !== "naac" && naac && !(o.naac && NAAC.indexOf(o.naac) <= NAAC.indexOf(naac) && NAAC.indexOf(o.naac) >= 0))
      return false;
    return o.feeTotal >= fee[0] && o.feeTotal <= fee[1];
  };
  const results = useMemo(() => offerings.filter((o) => matches(o)), [offerings, dq, level, programme, naac, fee]); // eslint-disable-line react-hooks/exhaustive-deps
  const groups = useMemo(() => groupOfferings(results), [results]);
  const facet = (key: "level" | "programme" | "naac", values: string[]) =>
    values.map((v) => ({
      v,
      n: offerings.filter(
        (o) =>
          matches(o, key) &&
          (key === "naac"
            ? !!o.naac && NAAC.indexOf(o.naac) >= 0 && NAAC.indexOf(o.naac) <= NAAC.indexOf(v)
            : (key === "level" ? o.level : o.programme) === v),
      ).length,
    }));
  const histogram = useMemo(() => {
    const b = new Array(16).fill(0) as number[];
    for (const o of offerings) b[Math.min(15, Math.floor(((o.feeTotal - feeMin) / (feeMax - feeMin || 1)) * 16))]! += 1;
    return b;
  }, [offerings, feeMin, feeMax]);

  const set =
    <T,>(fn: (v: T) => void) =>
    (v: T) =>
      startTransition(() => fn(v));
  const toggle = (s: Set<number>, id: number, max = 99) => {
    const n = new Set(s);
    if (n.has(id)) n.delete(id);
    else if (n.size < max) n.add(id);
    return n;
  };
  const applied = [
    level && { k: "level", label: level === "PG" ? "Postgraduate" : "Undergraduate", clear: () => setLevel(null) },
    programme && { k: "programme", label: programme, clear: () => setProgramme(null) },
    naac && { k: "naac", label: `NAAC ${naac} or better`, clear: () => setNaac(null) },
    (fee[0] !== feeMin || fee[1] !== feeMax) && {
      k: "fee",
      label: `${formatInrCompact(fee[0])} – ${formatInrCompact(fee[1])}`,
      clear: () => setFee([feeMin, feeMax]),
    },
  ].filter(Boolean) as { k: string; label: string; clear: () => void }[];

  const levelFacet = (
    <fieldset className="grid gap-2">
      <legend className="eyebrow mb-2">Level</legend>
      <div className="flex flex-wrap gap-2">
        {facet("level", ["UG", "PG"]).map(({ v, n }) => (
          <Chip
            key={v}
            selected={level === v}
            count={n}
            disabled={n === 0 && level !== v}
            onClick={() => set(setLevel)(level === v ? null : v)}
          >
            {v === "PG" ? "Postgraduate" : "Undergraduate"}
          </Chip>
        ))}
      </div>
    </fieldset>
  );
  const programmeFacet = (
    <fieldset className="grid gap-2">
      <legend className="eyebrow mb-2">Programme</legend>
      <div className="flex flex-wrap gap-2">
        {facet("programme", [...new Set(offerings.map((o) => o.programme))]).map(({ v, n }) => (
          <Chip
            key={v}
            selected={programme === v}
            count={n}
            disabled={n === 0 && programme !== v}
            onClick={() => set(setProgramme)(programme === v ? null : v)}
          >
            {v}
          </Chip>
        ))}
      </div>
    </fieldset>
  );
  const feeFacet = (
    <fieldset className="grid gap-2">
      <legend className="eyebrow mb-2">Total fee</legend>
      <RangeSlider
        min={feeMin}
        max={feeMax}
        step={5000}
        value={fee}
        onValueChange={set(setFee)}
        histogram={histogram}
        format={formatInrCompact}
        label="total fee"
      />
    </fieldset>
  );
  const naacFacet = (
    <fieldset className="grid gap-2">
      <legend className="eyebrow mb-2">NAAC grade</legend>
      <div className="flex flex-wrap gap-2">
        {facet("naac", NAAC).map(({ v, n }) => (
          <Chip
            key={v}
            selected={naac === v}
            count={n}
            disabled={n === 0 && naac !== v}
            onClick={() => set(setNaac)(naac === v ? null : v)}
          >
            {v}
            {v !== "A++" ? " or better" : ""}
          </Chip>
        ))}
      </div>
    </fieldset>
  );
  const facets = (
    <div className="grid gap-6">
      {levelFacet}
      {programmeFacet}
      {feeFacet}
      {naacFacet}
    </div>
  );
  const filterBar = (
    <div className="hidden flex-wrap items-center gap-2 lg:flex" role="group" aria-label="Filters">
      <FilterPopover label={level ? (level === "PG" ? "Postgraduate" : "Undergraduate") : "Level"} active={!!level}>
        {levelFacet}
      </FilterPopover>
      <FilterPopover label={programme ?? "Programme"} active={!!programme}>
        {programmeFacet}
      </FilterPopover>
      <FilterPopover
        label={
          fee[0] !== feeMin || fee[1] !== feeMax
            ? `${formatInrCompact(fee[0])} – ${formatInrCompact(fee[1])}`
            : "Total fee"
        }
        active={fee[0] !== feeMin || fee[1] !== feeMax}
      >
        {feeFacet}
      </FilterPopover>
      <FilterPopover label={naac ? `NAAC ${naac}+` : "NAAC grade"} active={!!naac}>
        {naacFacet}
      </FilterPopover>
    </div>
  );

  const siblings = open
    ? offerings.filter(
        (o) => o.programmeKey === open.programmeKey && o.specialisation === open.specialisation && o.id !== open.id,
      )
    : [];
  const groupFees = open ? [open, ...siblings].map((o) => o.feeTotal) : [0];

  return (
    <div className={cn("grid gap-6", variant === "a" ? "lg:grid-cols-[18rem_1fr]" : "")}>
      <div className={cn("lg:col-span-full")}>
        <label className="glass hairline-lumen flex h-14 items-center gap-3 rounded-full px-5 focus-within:shadow-[var(--glow-amber)]">
          <Search className="text-subtle size-5" aria-hidden />
          <span className="sr-only">Search programmes, specialisations or universities</span>
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Try “mba marketing” or “bca under 2 lakh”"
            className="text-text placeholder:text-subtle h-full min-w-0 flex-1 bg-transparent text-base outline-none"
          />
          <kbd className="border-border text-subtle hidden rounded-md border px-1.5 py-0.5 text-xs sm:block">⌘K</kbd>
        </label>
      </div>

      {variant === "a" ? <aside className="hidden lg:block">{facets}</aside> : null}

      <div className="grid min-w-0 content-start gap-4">
        {variant === "b" ? filterBar : null}
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-muted text-sm" aria-live="polite">
            <Odometer value={results.length} className="text-text font-semibold" /> offerings in{" "}
            <Odometer value={groups.length} className="text-text font-semibold" /> programmes
          </p>
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" className="lg:hidden" onClick={() => setSheet(true)}>
              <SlidersHorizontal aria-hidden /> Filters{applied.length ? ` (${applied.length})` : ""}
            </Button>
            <Segmented
              value={view}
              onValueChange={set(setView)}
              label="Results view"
              options={[
                { value: "grouped", label: "Grouped" },
                { value: "flat", label: "All offerings" },
              ]}
            />
          </div>
        </div>
        {applied.length ? (
          <div className="flex flex-wrap items-center gap-2">
            {applied.map((a) => (
              <Chip key={a.k} onRemove={() => startTransition(a.clear)}>
                {a.label}
              </Chip>
            ))}
            <button
              type="button"
              className="text-accent text-sm font-medium hover:underline"
              onClick={() =>
                startTransition(() => {
                  setLevel(null);
                  setProgramme(null);
                  setNaac(null);
                  setFee([feeMin, feeMax]);
                })
              }
            >
              Clear all
            </button>
          </div>
        ) : null}

        {results.length === 0 ? (
          <EmptyState
            icon={<Sparkles className="size-5" />}
            title="No exact matches"
            action={
              <Button variant="secondary">
                <Sparkles aria-hidden /> Ask Witty about “{q || "this"}”
              </Button>
            }
          >
            Try removing a filter{applied[0] ? ` such as “${applied[0].label}”` : ""}, or ask Witty — it can suggest
            close alternatives.
          </EmptyState>
        ) : view === "grouped" ? (
          <div className="grid gap-4">
            {groups.map((g) => (
              <GroupCard
                key={g.key}
                g={g}
                variant={variant}
                onOpen={(o) => startTransition(() => setOpen(o))}
                shortlist={shortlist}
                compare={compare}
                onShortlist={(id) => setShortlist((s) => toggle(s, id))}
                onCompare={(id) => setCompare((s) => toggle(s, id, 4))}
              />
            ))}
          </div>
        ) : (
          <ul className="glass grid gap-1 rounded-[var(--radius-xl)] p-2">
            {results.map((o) => (
              <OfferingRow
                key={o.id}
                o={o}
                onOpen={() => startTransition(() => setOpen(o))}
                shortlisted={shortlist.has(o.id)}
                compared={compare.has(o.id)}
                onShortlist={() => setShortlist((s) => toggle(s, o.id))}
                onCompare={() => setCompare((s) => toggle(s, o.id, 4))}
              />
            ))}
          </ul>
        )}
      </div>

      {compare.size ? (
        <div className="glass-strong fixed inset-x-3 bottom-3 z-[var(--z-dock)] mx-auto flex max-w-xl items-center justify-between gap-3 rounded-full py-2 pr-2 pl-5">
          <span className="text-text text-sm">
            <GitCompareArrows className="text-amber-text mr-1.5 inline size-4" aria-hidden />
            {compare.size} of 4 selected to compare
          </span>
          <Button size="sm">Compare</Button>
        </div>
      ) : null}

      <BottomSheet
        open={sheet}
        onOpenChange={setSheet}
        title="Filters"
        footer={
          <Button className="w-full" onClick={() => setSheet(false)}>
            Show {results.length} offerings
          </Button>
        }
      >
        {facets}
      </BottomSheet>

      <Panel
        open={!!open}
        onOpenChange={(v) => !v && setOpen(null)}
        title={open ? `${open.programme} · ${open.specialisation}` : ""}
        description={open?.university}
        footer={
          <div className="flex gap-2">
            <Button
              className="flex-1"
              onClick={() => document.getElementById("apply")?.scrollIntoView({ behavior: "smooth" })}
            >
              Apply now
            </Button>
            <Button variant="secondary" aria-label="Ask Witty about this programme">
              <Sparkles aria-hidden />
            </Button>
          </div>
        }
      >
        {open ? (
          <OfferingDetail
            o={open}
            siblings={siblings}
            feeRange={[Math.min(...groupFees), Math.max(...groupFees)]}
            onSwitch={(s) => setOpen(s)}
            onApply={() => {}}
            onAskWitty={() => {}}
          />
        ) : null}
      </Panel>
    </div>
  );
}
