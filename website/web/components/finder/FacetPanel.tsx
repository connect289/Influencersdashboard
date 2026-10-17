"use client";

import { useMemo, useState } from "react";
import { ChevronDown } from "lucide-react";
import { Chip } from "@/components/ui/Chip";
import dynamic from "next/dynamic";
import { QUALIFICATION_LABEL, type Qualification } from "@/lib/finder/eligibility";
import { formatCount, formatInrCompact } from "@/lib/format";
import { DURATION_LABEL, MODE_LABEL, NAAC_LABEL } from "@/lib/search/labels";
import { modeFromSql, naacFromSql, QUALS, type FinderParams } from "@/lib/search/state";
import type { FacetOption, Facets } from "@/lib/search/types";
import { cn } from "@/lib/utils";

type Change = (next: Partial<FinderParams>) => void;

const RangeSlider = dynamic(() => import("@/components/ui/RangeSlider").then((m) => m.RangeSlider), {
  ssr: false,
  loading: () => <div className="bg-surface h-[4.75rem] animate-pulse rounded-[var(--radius-md)]" aria-hidden />,
});

const toggle = (list: string[], v: string) => (list.includes(v) ? list.filter((x) => x !== v) : [...list, v]);

/** Collapsible facet section (native <details>: keyboard and screen-reader friendly, no JS state). */
function Section({ title, children, open = true, count }: { title: string; children: React.ReactNode; open?: boolean; count?: number }) {
  return (
    <details open={open} className="group border-border border-b py-4 last:border-b-0">
      <summary className="text-text flex cursor-pointer list-none items-center justify-between gap-2 text-sm font-semibold [&::-webkit-details-marker]:hidden">
        <span>
          {title}
          {count ? <span className="bg-primary text-on-primary ml-2 rounded-full px-1.5 text-[11px]">{count}</span> : null}
        </span>
        <ChevronDown className="text-subtle size-4 transition-transform group-open:rotate-180" aria-hidden />
      </summary>
      <div className="mt-3">{children}</div>
    </details>
  );
}

/** Checkbox list; zero-count options stay visible but disabled (spec 6.3) unless already selected. */
function CheckList({ name, options, selected, onToggle, limit = 8, searchable }: {
  name: string;
  options: FacetOption[];
  selected: string[];
  onToggle: (v: string) => void;
  limit?: number;
  searchable?: boolean;
}) {
  const [all, setAll] = useState(false);
  const [filter, setFilter] = useState("");
  const shown = useMemo(() => {
    const f = filter.trim().toLowerCase();
    const list = f ? options.filter((o) => o.label.toLowerCase().includes(f)) : options;
    // Selected first, then by availability, keeping the server order otherwise.
    const sorted = [...list].sort((a, b) => Number(selected.includes(b.value)) - Number(selected.includes(a.value)) || Number(b.count > 0) - Number(a.count > 0));
    return all || f ? sorted : sorted.slice(0, limit);
  }, [options, selected, all, filter, limit]);
  return (
    <fieldset className="grid gap-1">
      <legend className="sr-only">{name}</legend>
      {searchable && options.length > limit ? (
        <input
          type="search"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder={`Filter ${name.toLowerCase()}`}
          aria-label={`Filter ${name.toLowerCase()}`}
          className="border-border bg-bg-elev text-text placeholder:text-subtle mb-2 h-9 rounded-[var(--radius-md)] border px-3 text-sm"
        />
      ) : null}
      {shown.map((o) => {
        const checked = selected.includes(o.value);
        const disabled = o.count === 0 && !checked;
        return (
          <label
            key={o.value}
            className={cn(
              "hover:bg-surface-hover flex min-h-9 cursor-pointer items-center gap-3 rounded-[var(--radius-md)] px-2 text-sm",
              disabled && "cursor-not-allowed opacity-45 hover:bg-transparent",
            )}
          >
            <input type="checkbox" className="accent-[var(--primary)] size-4" checked={checked} disabled={disabled} onChange={() => onToggle(o.value)} />
            <span className={cn("min-w-0 flex-1 truncate", checked ? "text-text font-medium" : "text-muted")}>{o.label}</span>
            <span className="tabular text-subtle text-xs">{formatCount(o.count)}</span>
          </label>
        );
      })}
      {!filter && options.length > limit ? (
        <button type="button" className="text-accent mt-1 justify-self-start px-2 text-sm font-medium hover:underline" onClick={() => setAll((v) => !v)} aria-expanded={all}>
          {all ? "Show fewer" : `Show all ${options.length}`}
        </button>
      ) : null}
    </fieldset>
  );
}

function ChipRow({ options, selected, onToggle, label }: { options: { value: string; label: string; count: number }[]; selected: string[]; onToggle: (v: string) => void; label: string }) {
  return (
    <div className="flex flex-wrap gap-2" role="group" aria-label={label}>
      {options.map((o) => (
        <Chip key={o.value} selected={selected.includes(o.value)} count={o.count} disabled={o.count === 0 && !selected.includes(o.value)} onClick={() => onToggle(o.value)}>
          {o.label}
        </Chip>
      ))}
    </div>
  );
}

function FeeFacet({ facets, params, onChange }: { facets: Facets; params: FinderParams; onChange: Change }) {
  const lo = facets.fee.global_min ?? 0;
  const hi = facets.fee.global_max ?? 500000;
  const step = 5000;
  const floor = Math.floor(lo / step) * step;
  const ceil = Math.ceil(hi / step) * step;
  const [value, setValue] = useState<[number, number]>([params.fee_min ?? floor, params.fee_max ?? ceil]);
  const commit = (v: [number, number]) => onChange({ fee_min: v[0] > floor ? v[0] : undefined, fee_max: v[1] < ceil ? v[1] : undefined });
  const presets: { label: string; min?: number; max?: number }[] = [
    { label: "Under ₹1 lakh", max: 100000 },
    { label: "₹1–2 lakh", min: 100000, max: 200000 },
    { label: "₹2–3 lakh", min: 200000, max: 300000 },
    { label: "Above ₹3 lakh", min: 300000 },
  ];
  return (
    <div className="grid gap-4">
      <RangeSlider min={floor} max={ceil} step={step} value={value} onValueChange={setValue} onValueCommit={commit} histogram={facets.fee.histogram} format={formatInrCompact} label="total fee" />
      <div className="flex flex-wrap gap-2" role="group" aria-label="Fee presets">
        {presets.map((p) => {
          const on = params.fee_min === p.min && params.fee_max === p.max;
          return (
            <Chip
              key={p.label}
              selected={on}
              onClick={() => {
                const v: [number, number] = [p.min ?? floor, p.max ?? ceil];
                setValue(v);
                onChange(on ? { fee_min: undefined, fee_max: undefined } : { fee_min: p.min, fee_max: p.max });
              }}
            >
              {p.label}
            </Chip>
          );
        })}
      </div>
      {facets.fee.on_request ? (
        <p className="text-subtle text-xs">
          {formatCount(facets.fee.on_request)} offerings publish their fee on request; a fee filter leaves them out.
        </p>
      ) : null}
    </div>
  );
}

/**
 * All finder facets (spec 6.3) for the desktop rail and the mobile sheet. Counts come from the server with every other
 * filter applied; options with zero results are disabled, not hidden; choosing a programme narrows specialisations.
 */
export function FacetPanel({ facets, params, onChange, total }: { facets: Facets; params: FinderParams; onChange: Change; total: number }) {
  const progByLevel = useMemo(() => {
    const groups = new Map<string, FacetOption[]>();
    for (const o of facets.programme) {
      const k = o.level ?? "other";
      groups.set(k, [...(groups.get(k) ?? []), o]);
    }
    return [...groups.entries()];
  }, [facets.programme]);
  const levelLabel = (id: string) => facets.level.find((l) => l.value === id)?.label ?? id;
  const elig = facets.eligibility;

  return (
    <div className="grid">
      <Section title="I have completed" count={params.qual ? 1 : 0}>
        <div className="flex flex-wrap gap-2" role="group" aria-label="Your highest qualification">
          {QUALS.map((q) => (
            <Chip key={q} selected={params.qual === q} onClick={() => onChange({ qual: params.qual === q ? undefined : q, all: false })}>
              {QUALIFICATION_LABEL[q as Qualification]}
            </Chip>
          ))}
        </div>
        {params.qual && elig ? (
          <label className="text-muted mt-3 flex items-center gap-2 text-sm">
            <input type="checkbox" className="accent-[var(--primary)] size-4" checked={params.all} onChange={() => onChange({ all: !params.all })} />
            Show programmes I may not be eligible for ({formatCount(elig.not_eligible)})
          </label>
        ) : (
          <p className="text-subtle mt-2 text-xs">We&apos;ll mark what you&apos;re eligible for.</p>
        )}
      </Section>

      {facets.goal.some((g) => g.count > 0) ? (
        <Section title="My goal" open={!!params.goal} count={params.goal ? 1 : 0}>
          <ChipRow label="Goal" options={facets.goal} selected={params.goal ? [params.goal] : []} onToggle={(v) => onChange({ goal: params.goal === v ? undefined : v })} />
        </Section>
      ) : null}

      <Section title="Level" count={params.level.length}>
        <ChipRow label="Level" options={facets.level} selected={params.level} onToggle={(v) => onChange({ level: toggle(params.level, v) })} />
      </Section>

      <Section title="Programme" count={params.programme.length}>
        <div className="grid gap-3">
          {progByLevel.map(([lvl, opts]) => (
            <div key={lvl}>
              <p className="eyebrow mb-1 px-2">{levelLabel(lvl)}</p>
              <CheckList name="Programme" options={opts} selected={params.programme} onToggle={(v) => onChange({ programme: toggle(params.programme, v) })} limit={12} />
            </div>
          ))}
        </div>
      </Section>

      <Section title="Specialisation" count={params.spec.length}>
        <CheckList name="Specialisation" options={facets.spec} selected={params.spec} onToggle={(v) => onChange({ spec: toggle(params.spec, v) })} limit={10} searchable />
      </Section>

      <Section title="Total fee" count={params.fee_min || params.fee_max ? 1 : 0}>
        <FeeFacet key={`${params.fee_min}-${params.fee_max}`} facets={facets} params={params} onChange={onChange} />
      </Section>

      <Section title="Duration" count={params.duration.length}>
        <ChipRow label="Duration" options={facets.duration.map((d) => ({ ...d, label: DURATION_LABEL[d.value] ?? d.label }))} selected={params.duration} onToggle={(v) => onChange({ duration: toggle(params.duration, v) })} />
      </Section>

      <Section title="Mode" count={params.mode.length}>
        <ChipRow
          label="Mode"
          options={facets.mode.map((m) => ({ value: modeFromSql(m.value), label: MODE_LABEL[modeFromSql(m.value)] ?? m.label, count: m.count }))}
          selected={params.mode}
          onToggle={(v) => onChange({ mode: toggle(params.mode, v) as FinderParams["mode"] })}
        />
      </Section>

      <Section title="University" count={params.uni.length} open={params.uni.length > 0}>
        <CheckList name="University" options={facets.university} selected={params.uni} onToggle={(v) => onChange({ uni: toggle(params.uni, v) })} limit={8} searchable />
      </Section>

      <Section title="Approvals and rankings" count={[params.ugc, params.aicte, params.nirf].filter(Boolean).length + params.naac.length}>
        <div className="grid gap-3">
          <ChipRow
            label="NAAC grade"
            options={facets.naac.map((n) => ({ value: naacFromSql(n.value), label: NAAC_LABEL[naacFromSql(n.value)] ?? n.label, count: n.count }))}
            selected={params.naac}
            onToggle={(v) => onChange({ naac: toggle(params.naac, v) })}
          />
          <div className="flex flex-wrap gap-2" role="group" aria-label="Approvals">
            <Chip selected={params.ugc} count={facets.ugc_deb} disabled={!facets.ugc_deb && !params.ugc} onClick={() => onChange({ ugc: !params.ugc })}>
              UGC-DEB stated
            </Chip>
            <Chip selected={params.aicte} count={facets.aicte} disabled={!facets.aicte && !params.aicte} onClick={() => onChange({ aicte: !params.aicte })}>
              AICTE
            </Chip>
            <Chip selected={params.nirf} count={facets.nirf} disabled={!facets.nirf && !params.nirf} onClick={() => onChange({ nirf: !params.nirf })}>
              NIRF ranked
            </Chip>
          </div>
        </div>
      </Section>

      <Section title="Eligibility requirements" open={false} count={params.minq.length + (params.workex ? 1 : 0) + (params.entrance ? 1 : 0)}>
        <div className="grid gap-3">
          <ChipRow
            label="Minimum qualification"
            options={facets.min_q.map((m) => ({ value: m.value.toLowerCase(), label: `Needs ${m.label.toLowerCase()}`, count: m.count }))}
            selected={params.minq}
            onToggle={(v) => onChange({ minq: toggle(params.minq, v) })}
          />
          <div className="flex flex-wrap gap-2" role="group" aria-label="Work experience">
            <Chip selected={params.workex === "not_required"} count={facets.work_exp.not_required} onClick={() => onChange({ workex: params.workex === "not_required" ? undefined : "not_required" })}>
              No work experience needed
            </Chip>
            <Chip selected={params.workex === "required"} count={facets.work_exp.required} disabled={!facets.work_exp.required && params.workex !== "required"} onClick={() => onChange({ workex: params.workex === "required" ? undefined : "required" })}>
              Work experience required
            </Chip>
          </div>
          {facets.entrance.yes + facets.entrance.no > 0 ? (
            <div className="flex flex-wrap gap-2" role="group" aria-label="Entrance exam">
              <Chip selected={params.entrance === "no"} count={facets.entrance.no} onClick={() => onChange({ entrance: params.entrance === "no" ? undefined : "no" })}>
                No entrance exam
              </Chip>
              <Chip selected={params.entrance === "yes"} count={facets.entrance.yes} onClick={() => onChange({ entrance: params.entrance === "yes" ? undefined : "yes" })}>
                Entrance exam
              </Chip>
            </div>
          ) : null}
        </div>
      </Section>

      <Section title="Programme format" open={params.format.length > 0} count={params.format.length}>
        <ChipRow label="Programme format" options={facets.format.filter((f) => f.count > 0 || params.format.includes(f.value))} selected={params.format} onToggle={(v) => onChange({ format: toggle(params.format, v) })} />
      </Section>

      {facets.state.length ? (
        <Section title="University state" open={params.state.length > 0} count={params.state.length}>
          <CheckList name="State" options={facets.state} selected={params.state} onToggle={(v) => onChange({ state: toggle(params.state, v) })} />
        </Section>
      ) : null}

      <p className="text-subtle pt-4 text-xs" aria-live="polite">
        {formatCount(total)} offerings match.
      </p>
    </div>
  );
}
