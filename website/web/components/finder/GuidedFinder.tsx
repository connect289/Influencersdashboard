"use client";

import { useState } from "react";
import { ArrowLeft, Check, Compass, X } from "lucide-react";
import { Chip } from "@/components/ui/Chip";
import { ProgressTrack } from "@/components/ui/DataViz";
import { QUALIFICATION_LABEL, type Qualification } from "@/lib/finder/eligibility";
import { formatCount } from "@/lib/format";
import { DURATION_LABEL } from "@/lib/search/labels";
import { QUALS, type FinderParams } from "@/lib/search/state";
import type { Facets } from "@/lib/search/types";
import { cn } from "@/lib/utils";

const BUDGETS = [
  { label: "Under ₹1 lakh", max: 100000 },
  { label: "Under ₹2 lakh", max: 200000 },
  { label: "Under ₹3 lakh", max: 300000 },
  { label: "Any budget" },
] as const;

/**
 * Guided finder (spec 6.1): "I have completed…" → "I want to…" → optional budget and duration. Each answer is applied
 * to the URL immediately, so results narrow live behind it; every step can be revisited and changed.
 */
export function GuidedFinder({ params, facets, total, onChange, onClose }: {
  params: FinderParams;
  facets: Facets;
  total: number;
  onChange: (next: Partial<FinderParams>) => void;
  onClose: () => void;
}) {
  const [step, setStep] = useState(params.qual ? (params.goal ? 2 : 1) : 0);
  const steps = ["Your studies", "Your goal", "Budget and time"];
  return (
    <section className="glass-strong hairline-lumen grid gap-5 rounded-[var(--radius-2xl)] p-5 sm:p-6" aria-labelledby="guided-title">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-3">
          <span className="bg-amber-soft text-amber-text grid size-10 place-items-center rounded-full">
            <Compass className="size-5" aria-hidden />
          </span>
          <div>
            <h2 id="guided-title" className="font-display text-text text-lg font-semibold">
              Find programmes that fit you
            </h2>
            <p className="text-muted text-sm" aria-live="polite">
              Step {step + 1} of 3 · <span className="tabular text-text font-medium">{formatCount(total)}</span> offerings match so far
            </p>
          </div>
        </div>
        <button type="button" onClick={onClose} className="text-muted hover:bg-surface-hover grid size-9 place-items-center rounded-full" aria-label="Close the guided finder">
          <X className="size-4" aria-hidden />
        </button>
      </div>
      <ProgressTrack step={step + 1} total={3} labels={steps} label="Guided finder progress" />

      {step === 0 ? (
        <fieldset>
          <legend className="text-text mb-3 font-medium">I have completed…</legend>
          <div className="flex flex-wrap gap-2">
            {QUALS.map((q) => (
              <Chip key={q} selected={params.qual === q} onClick={() => { onChange({ qual: q, all: false }); setStep(1); }}>
                {QUALIFICATION_LABEL[q as Qualification]}
              </Chip>
            ))}
          </div>
        </fieldset>
      ) : step === 1 ? (
        <fieldset>
          <legend className="text-text mb-3 font-medium">I want to…</legend>
          <div className="grid gap-2 sm:grid-cols-2">
            {facets.goal.map((g) => {
              const on = params.goal === g.value;
              return (
                <button
                  key={g.value}
                  type="button"
                  aria-pressed={on}
                  disabled={g.count === 0 && !on}
                  onClick={() => { onChange({ goal: on ? undefined : g.value }); if (!on) setStep(2); }}
                  className={cn(
                    "flex items-center justify-between gap-3 rounded-[var(--radius-lg)] border px-4 py-3 text-left text-sm transition-colors disabled:cursor-not-allowed disabled:opacity-45",
                    on ? "border-primary bg-amber-soft text-text" : "border-border bg-surface text-muted hover:text-text",
                  )}
                >
                  <span>{g.label}</span>
                  <span className="tabular text-subtle text-xs">{on ? <Check className="text-amber-text size-4" aria-hidden /> : formatCount(g.count)}</span>
                </button>
              );
            })}
          </div>
          <button type="button" className="text-accent mt-3 text-sm font-medium hover:underline" onClick={() => setStep(2)}>
            Skip this step
          </button>
        </fieldset>
      ) : (
        <div className="grid gap-5">
          <fieldset>
            <legend className="text-text mb-3 font-medium">My budget for the whole programme (optional)</legend>
            <div className="flex flex-wrap gap-2">
              {BUDGETS.map((b) => {
                const max = "max" in b ? b.max : undefined;
                const on = params.fee_max === max && !params.fee_min;
                return (
                  <Chip key={b.label} selected={on} onClick={() => onChange({ fee_max: max, fee_min: undefined })}>
                    {b.label}
                  </Chip>
                );
              })}
            </div>
          </fieldset>
          <fieldset>
            <legend className="text-text mb-3 font-medium">How long can I study? (optional)</legend>
            <div className="flex flex-wrap gap-2">
              {facets.duration.map((d) => (
                <Chip key={d.value} selected={params.duration.includes(d.value)} count={d.count} disabled={d.count === 0 && !params.duration.includes(d.value)}
                  onClick={() => onChange({ duration: params.duration.includes(d.value) ? [] : [d.value] })}>
                  {DURATION_LABEL[d.value]}
                </Chip>
              ))}
            </div>
          </fieldset>
          <button type="button" onClick={onClose} className="bg-primary text-on-primary h-11 justify-self-start rounded-full px-6 text-sm font-semibold">
            See {formatCount(total)} results
          </button>
        </div>
      )}
      {step > 0 ? (
        <button type="button" onClick={() => setStep(step - 1)} className="text-muted hover:text-text inline-flex items-center gap-1.5 justify-self-start text-sm">
          <ArrowLeft className="size-4" aria-hidden /> Back to {steps[step - 1]!.toLowerCase()}
        </button>
      ) : null}
    </section>
  );
}
