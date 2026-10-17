"use client";

import { Check, CircleHelp, GitCompareArrows, Heart } from "lucide-react";
import { Badge } from "@/components/ui/Badge";
import { formatInr, formatInrCompact } from "@/lib/format";
import type { SeedOffering } from "@/lib/seed/concept";
import { cn } from "@/lib/utils";

const delay = (i: number, step = 110) => ({ animationDelay: `${i * step}ms` });

/** Programme cards that assemble into the chat (spec 10.3 generative UI). */
export function ProgrammeCards({ items, onOpen }: { items: SeedOffering[]; onOpen?: (o: SeedOffering) => void }) {
  return (
    <ul className="grid gap-2 sm:grid-cols-3">
      {items.map((o, i) => (
        <li
          key={o.id}
          className="animate-rise hairline-lumen bg-surface rounded-[var(--radius-lg)] p-3.5"
          style={delay(i)}
        >
          <p className="text-subtle text-xs">{o.universityShort}</p>
          <p className="text-text mt-0.5 leading-snug font-semibold">
            {o.programme} · {o.specialisation}
          </p>
          <p className="tabular font-display text-text mt-2 text-xl font-semibold">{formatInr(o.feeTotal)}</p>
          <p className="text-amber-text text-xs">Easy EMI available</p>
          <div className="mt-2 flex flex-wrap gap-1">
            {o.naac ? <Badge tone="verified">NAAC {o.naac}</Badge> : null}
          </div>
          <div className="mt-3 flex items-center gap-1">
            <button
              type="button"
              onClick={() => onOpen?.(o)}
              className="bg-primary text-on-primary h-9 flex-1 rounded-full px-3 text-sm font-semibold"
            >
              Details
            </button>
            <button
              type="button"
              aria-label={`Shortlist ${o.university}`}
              className="border-border text-muted hover:text-text grid size-9 place-items-center rounded-full border"
            >
              <Heart className="size-4" aria-hidden />
            </button>
            <button
              type="button"
              aria-label={`Compare ${o.university}`}
              className="border-border text-muted hover:text-text grid size-9 place-items-center rounded-full border"
            >
              <GitCompareArrows className="size-4" aria-hidden />
            </button>
          </div>
        </li>
      ))}
    </ul>
  );
}

/** Fee bars that fill to each programme's total fee. */
export function FeeBreakdown({ items }: { items: SeedOffering[] }) {
  const max = Math.max(...items.map((o) => o.feeTotal));
  return (
    <div
      className="border-border grid gap-2.5 rounded-[var(--radius-lg)] border p-4"
      role="group"
      aria-label="Fee comparison"
    >
      {items.map((o, i) => (
        <div key={o.id} className="grid grid-cols-[6rem_1fr_auto] items-center gap-3 text-sm">
          <span className="text-muted truncate">{o.universityShort}</span>
          <span className="bg-border relative h-2.5 overflow-hidden rounded-full">
            <span
              className="fee-bar-fill absolute inset-y-0 left-0 rounded-full bg-gradient-to-r from-amber-300 to-amber-600"
              style={{ width: `${(o.feeTotal / max) * 100}%`, ...delay(i, 160) }}
            />
          </span>
          <span className="tabular text-text font-medium">{formatInrCompact(o.feeTotal)}</span>
        </div>
      ))}
    </div>
  );
}

/** Eligibility checks that tick one by one. "unknown" items say a counsellor will confirm (never a guess). */
export function EligibilityChecklist({ items }: { items: { label: string; status: "ok" | "unknown" }[] }) {
  return (
    <ul className="border-border grid gap-2 rounded-[var(--radius-lg)] border p-4">
      {items.map((it, i) => (
        <li key={it.label} className="animate-rise flex items-center gap-2.5 text-sm" style={delay(i, 220)}>
          <span
            className={cn(
              "grid size-6 place-items-center rounded-full",
              it.status === "ok" ? "bg-success-soft text-success" : "bg-warning-soft text-warning",
            )}
          >
            {it.status === "ok" ? (
              <Check className="size-3.5" strokeWidth={3} aria-hidden />
            ) : (
              <CircleHelp className="size-3.5" aria-hidden />
            )}
          </span>
          <span className="text-text">{it.label}</span>
          <span className="sr-only">{it.status === "ok" ? "meets the requirement" : "a counsellor will confirm"}</span>
        </li>
      ))}
    </ul>
  );
}

/** Comparison grid built column by column; differences highlighted by light (best value glows). */
export function ComparisonGrid({ items }: { items: SeedOffering[] }) {
  const minFee = Math.min(...items.map((o) => o.feeTotal));
  const order = ["B", "B+", "B++", "A", "A+", "A++"];
  const best = items.map((o) => order.indexOf(o.naac ?? "")).reduce((a, b) => Math.max(a, b), -1);
  const rows: { label: string; cell: (o: SeedOffering) => React.ReactNode; win?: (o: SeedOffering) => boolean }[] = [
    {
      label: "Total fee",
      cell: (o) => <span className="tabular">{formatInr(o.feeTotal)}</span>,
      win: (o) => o.feeTotal === minFee,
    },
    { label: "Duration", cell: (o) => (o.durationYears ? `${o.durationYears} years` : "Ask a counsellor") },
    {
      label: "NAAC",
      cell: (o) => o.naac ?? "Not stated",
      win: (o) => order.indexOf(o.naac ?? "") === best && best >= 0,
    },
    { label: "UGC-DEB", cell: (o) => (o.ugcDeb ? "Entitled" : "Not stated") },
    { label: "Mode", cell: (o) => o.mode },
    { label: "EMI", cell: () => "Easy EMI available" },
  ];
  return (
    <div className="border-border overflow-x-auto rounded-[var(--radius-lg)] border">
      <table className="w-full min-w-[30rem] border-collapse text-sm">
        <caption className="sr-only">Comparison of selected programmes</caption>
        <thead>
          <tr>
            <th scope="col" className="text-subtle w-28 p-3 text-left text-xs font-medium" />
            {items.map((o, i) => (
              <th
                key={o.id}
                scope="col"
                className="animate-rise text-text p-3 text-left font-semibold"
                style={delay(i, 180)}
              >
                {o.universityShort}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.label} className="border-border border-t">
              <th scope="row" className="text-subtle p-3 text-left text-xs font-medium">
                {r.label}
              </th>
              {items.map((o, i) => (
                <td
                  key={o.id}
                  className={cn(
                    "animate-rise text-text p-3",
                    r.win?.(o) &&
                      "bg-amber-soft font-semibold shadow-[inset_0_0_0_1px_color-mix(in_oklab,var(--primary)_35%,transparent)]",
                  )}
                  style={delay(i, 180)}
                >
                  {r.cell(o)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
