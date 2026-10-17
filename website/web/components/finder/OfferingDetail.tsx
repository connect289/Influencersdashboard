"use client";

import { BadgeCheck, CalendarCheck, Clock, GraduationCap, Info, MessageCircle, Monitor, Sparkles } from "lucide-react";
import { Accordion } from "@/components/ui/Accordion";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { FeeBar, GradeMeter } from "@/components/ui/DataViz";
import { formatDate, formatInr } from "@/lib/format";
import type { SeedOffering } from "@/lib/seed/concept";

const QUAL: Record<string, string> = {
  "12TH": "Class 12 pass",
  BACHELOR: "Bachelor's degree",
  MASTER: "Master's degree",
  DIPLOMA: "Diploma",
};

/**
 * Offering detail panel body (spec 6.6). Shows only what the catalogue has — missing fields do not appear (no empty
 * headings, no "N/A"). Every fee carries "Easy EMI available", the last-verified date and the disclaimer (spec 14).
 */
export function OfferingDetail({
  o,
  siblings,
  onSwitch,
  onApply,
  onAskWitty,
  feeRange,
}: {
  o: SeedOffering;
  siblings: SeedOffering[];
  onSwitch: (o: SeedOffering) => void;
  onApply: () => void;
  onAskWitty: () => void;
  feeRange: [number, number];
}) {
  const facts: { icon: React.ReactNode; label: string; value: React.ReactNode }[] = [];
  if (o.durationYears)
    facts.push({ icon: <Clock aria-hidden />, label: "Duration", value: `${o.durationYears} years` });
  facts.push({ icon: <Monitor aria-hidden />, label: "Mode", value: o.mode });
  if (QUAL[o.minQualification])
    facts.push({
      icon: <GraduationCap aria-hidden />,
      label: "Eligibility",
      value: `${QUAL[o.minQualification]}${o.minPct ? `, ${o.minPct}% minimum` : ""}`,
    });

  return (
    <div className="grid gap-6">
      <section className="hairline-lumen bg-surface rounded-[var(--radius-xl)] p-5">
        <p className="eyebrow">Full programme fee</p>
        <p className="tabular font-display text-text mt-1 text-4xl font-semibold">{formatInr(o.feeTotal)}</p>
        <p className="text-muted mt-1 text-sm">
          {o.feeSemester
            ? `${formatInr(o.feeSemester)} per semester`
            : o.feeYearly
              ? `${formatInr(o.feeYearly)} per year`
              : "Total for the full programme"}
          <span className="text-amber-text font-medium"> · Easy EMI available</span>
        </p>
        <FeeBar
          className="mt-4"
          value={o.feeTotal}
          min={feeRange[0]}
          max={feeRange[1]}
          label={`Fee position within the range of similar programmes`}
        />
        <p className="text-subtle mt-1 flex justify-between text-xs">
          <span>Lowest similar {formatInr(feeRange[0])}</span>
          <span>Highest {formatInr(feeRange[1])}</span>
        </p>
      </section>

      <dl className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        {facts.map((f) => (
          <div
            key={f.label}
            className="border-border [&_svg]:text-amber-text rounded-[var(--radius-lg)] border p-4 [&_svg]:size-5"
          >
            {f.icon}
            <dt className="text-subtle mt-2 text-xs">{f.label}</dt>
            <dd className="text-text mt-0.5 font-medium">{f.value}</dd>
          </div>
        ))}
      </dl>

      <section className="grid gap-3">
        <h3 className="text-base font-semibold">Approvals and accreditation</h3>
        <div className="flex flex-wrap items-center gap-3">
          {o.ugcDeb ? <Badge tone="verified">UGC-DEB entitled</Badge> : null}
          {o.aicte ? <Badge tone="info">AICTE</Badge> : null}
          {o.naac ? <GradeMeter grade={o.naac} /> : null}
        </div>
        <Accordion
          items={[
            {
              id: "deb",
              title: "What UGC-DEB entitlement means",
              content:
                "The University Grants Commission's Distance Education Bureau (UGC-DEB) publishes which universities may offer which programmes online or in open and distance learning (ODL) mode, and for which period. Your counsellor can show you the university's current listing.",
            },
            {
              id: "naac",
              title: "What the NAAC grade tells you",
              content:
                "NAAC (National Assessment and Accreditation Council) grades universities on teaching, research and infrastructure. A++ is the highest grade.",
            },
          ]}
        />
      </section>

      <p className="bg-bg-sunken text-muted flex items-start gap-2 rounded-[var(--radius-md)] p-3 text-xs">
        <Info className="mt-0.5 size-4 shrink-0" aria-hidden />
        <span>
          <span className="text-text flex items-center gap-1 font-medium">
            <CalendarCheck className="size-3.5" aria-hidden /> Data last verified: {formatDate(o.verifiedAt)}
          </span>
          Fees are set by universities and may change; confirm with your counsellor.
        </span>
      </p>

      {siblings.length ? (
        <section className="grid gap-2">
          <h3 className="text-base font-semibold">Also offered by</h3>
          <ul className="grid gap-1">
            {siblings.slice(0, 5).map((s) => (
              <li key={s.id}>
                <button
                  type="button"
                  onClick={() => onSwitch(s)}
                  className="hover:bg-surface-hover flex w-full items-center justify-between gap-3 rounded-[var(--radius-md)] px-3 py-2.5 text-left"
                >
                  <span className="text-text truncate">{s.university}</span>
                  <span className="tabular text-muted shrink-0 text-sm">{formatInr(s.feeTotal)}</span>
                </button>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <section id="apply" className="hairline-lumen bg-surface grid gap-3 rounded-[var(--radius-xl)] p-5">
        <div className="flex items-center gap-2">
          <BadgeCheck className="text-success size-5" aria-hidden />
          <h3 className="text-base font-semibold">Apply with Eduwit — free support</h3>
        </div>
        <p className="text-muted text-sm">
          A short pre-application: we collect your details and a counsellor completes the university application with
          you. No payment here.
        </p>
        <div className="flex flex-wrap gap-2">
          <Button onClick={onApply} magnetic>
            Start application
          </Button>
          <Button variant="secondary" onClick={onAskWitty}>
            <Sparkles aria-hidden /> Ask Witty about this programme
          </Button>
        </div>
        <p className="text-subtle flex items-center gap-1.5 text-xs">
          <MessageCircle className="size-3.5" aria-hidden /> Prefer to talk? A counsellor can call or WhatsApp you.
        </p>
      </section>
    </div>
  );
}
