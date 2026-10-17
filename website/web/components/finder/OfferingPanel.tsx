"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { ArrowRight, BadgeCheck, CalendarCheck, Info, Loader2 } from "lucide-react";
import { Badge } from "@/components/ui/Badge";
import { Panel } from "@/components/ui/Panel";
import { EXPLAINERS } from "@/content/explainers";
import { FEE_DISCLAIMER } from "@/content/site";
import { track } from "@/lib/client/analytics";
import { setOfferingParam } from "@/lib/client/use-finder";
import { MIN_QUALIFICATION_LABEL } from "@/lib/finder/eligibility";
import { formatDate, formatDuration, formatInr } from "@/lib/format";
import { ATTRIBUTE_LABEL, FORMAT_LABEL, UGC_LABEL } from "@/lib/search/labels";
import type { OfferingDetails } from "@/lib/search/types";
import { AskWitty } from "./AskWitty";
import { EligibilityBadge, ShortlistCompareButtons } from "./OfferingResult";

function Fact({ label, children, note }: { label: string; children: React.ReactNode; note?: string }) {
  return (
    <div className="border-border rounded-[var(--radius-lg)] border p-3">
      <dt className="text-subtle text-xs">{label}</dt>
      <dd className="text-text mt-0.5 font-medium">{children}</dd>
      {note ? <dd className="text-subtle mt-0.5 text-xs">{note}</dd> : null}
    </div>
  );
}

function Explain({ title, body }: { title: string; body: string }) {
  return (
    <details className="group mt-1">
      <summary className="text-accent inline-flex cursor-pointer list-none items-center gap-1 text-xs font-medium [&::-webkit-details-marker]:hidden">
        <Info className="size-3.5" aria-hidden /> {title}
      </summary>
      <p className="text-muted mt-1 text-xs leading-relaxed">{body}</p>
    </details>
  );
}

/**
 * Offering detail panel (spec 6.6): right drawer on desktop, full-screen sheet on mobile, deep-linkable with
 * `?offering=<id>`, closes back to the same results. Shows only what the catalogue has — missing fields don't appear.
 */
export function OfferingPanel({ qual, advisorEnabled, whatsapp }: { qual?: string; advisorEnabled: boolean; whatsapp: string }) {
  const sp = useSearchParams();
  const id = Number(sp.get("offering")) || null;
  const [res, setRes] = useState<{ id: number; data: OfferingDetails | null; status: "ok" | "error" | "missing" } | null>(null);

  useEffect(() => {
    if (!id) return;
    const ctrl = new AbortController();
    fetch(`/api/offerings/${id}${qual ? `?qual=${qual}` : ""}`, { signal: ctrl.signal })
      .then(async (r) => {
        if (r.status === 404) return setRes({ id, data: null, status: "missing" });
        if (!r.ok) throw new Error(String(r.status));
        const d = (await r.json()) as OfferingDetails;
        setRes({ id, data: d, status: "ok" });
        if (d.moved_from) setOfferingParam(d.id, "replace");
        track("offering_view", { offering_id: d.id, programme: d.programme_id, university_id: d.university.id });
        track("panel_open", { kind: "offering" });
      })
      .catch((e: unknown) => {
        if ((e as Error).name !== "AbortError") setRes({ id, data: null, status: "error" });
      });
    return () => ctrl.abort();
  }, [id, qual]);

  const open = !!id;
  const close = () => setOfferingParam(null, "push");
  // A replaced offering answers for the old id; after the URL is updated the new id matches too.
  const current = res && (res.id === id || res.data?.id === id) ? res : null;
  const d = current?.data ?? null;
  const state = !id ? "idle" : !current ? "loading" : current.status === "ok" ? "idle" : current.status;
  const f = d?.university_facts;
  const attrs = d ? (Object.entries(d.attributes ?? {}).map(([k, v]) => (k === "medium" ? `${v} medium` : ATTRIBUTE_LABEL[k])).filter(Boolean) as string[]) : [];

  return (
    <Panel
      open={open}
      onOpenChange={(v) => !v && close()}
      title={d ? `${d.programme_name} · ${d.spec_name}` : state === "missing" ? "Programme not found" : "Loading…"}
      description={d ? d.university.name : undefined}
      footer={
        d ? (
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => document.getElementById("apply")?.scrollIntoView({ behavior: "smooth", block: "start" })}
              className="bg-primary text-on-primary inline-flex h-11 flex-1 items-center justify-center rounded-full text-sm font-semibold"
            >
              Apply now
            </button>
            <ShortlistCompareButtons o={d} />
          </div>
        ) : null
      }
    >
      {state === "loading" && !d ? (
        <p className="text-muted flex items-center gap-2" role="status">
          <Loader2 className="size-4 animate-spin" aria-hidden /> Loading programme details…
        </p>
      ) : state === "missing" ? (
        <div className="grid gap-3">
          <p className="text-muted">This programme is no longer listed. It may have been renamed or withdrawn by the university.</p>
          <button type="button" onClick={close} className="text-accent justify-self-start font-medium hover:underline">
            Back to results
          </button>
        </div>
      ) : state === "error" && !d ? (
        <p className="text-danger" role="alert">
          We couldn&apos;t load this programme. Check your connection and try again.
        </p>
      ) : d ? (
        <div className="grid gap-6">
          <section aria-labelledby="fee-h">
            <h3 id="fee-h" className="sr-only">Fees</h3>
            {d.fee.total ? (
              <div className="glass rounded-[var(--radius-xl)] p-4">
                <p className="text-subtle text-xs">Total programme fee</p>
                <p className="tabular font-display text-text text-3xl font-semibold">{formatInr(d.fee.total)}</p>
                <p className="text-muted mt-1 text-sm">
                  {[d.fee.yearly ? `${formatInr(d.fee.yearly)} per year` : null, d.fee.semester ? `${formatInr(d.fee.semester)} per semester` : null].filter(Boolean).join(" · ")}
                </p>
                <p className="text-amber-text mt-2 text-sm font-medium">Easy EMI available</p>
                {d.fee_registration || d.fee_exam || d.fee_lines?.length ? (
                  <details className="mt-3">
                    <summary className="text-accent cursor-pointer text-sm font-medium">Fee breakdown</summary>
                    <dl className="mt-2 grid gap-1 text-sm">
                      {d.fee_registration ? (
                        <div className="flex justify-between gap-3"><dt className="text-muted">Registration</dt><dd className="tabular text-text">{formatInr(d.fee_registration)}</dd></div>
                      ) : null}
                      {d.fee_exam ? (
                        <div className="flex justify-between gap-3"><dt className="text-muted">Exam fee</dt><dd className="tabular text-text">{formatInr(d.fee_exam)}</dd></div>
                      ) : null}
                      {d.fee_lines?.map((l) => (
                        <div key={l.label} className="flex justify-between gap-3"><dt className="text-muted">{l.label}</dt><dd className="tabular text-text">{formatInr(l.amount)}</dd></div>
                      ))}
                    </dl>
                  </details>
                ) : null}
              </div>
            ) : (
              <div className="glass rounded-[var(--radius-xl)] p-4">
                <p className="text-text font-medium">Fee on request</p>
                <p className="text-muted text-sm">The university shares this fee on enquiry. A counsellor can confirm it for you.</p>
              </div>
            )}
            <p className="text-subtle mt-2 text-xs">{FEE_DISCLAIMER}</p>
          </section>

          <section aria-labelledby="facts-h">
            <h3 id="facts-h" className="eyebrow mb-2">Key facts</h3>
            <dl className="grid grid-cols-2 gap-2">
              <Fact label="Level">{d.level_label}</Fact>
              {d.mode ? <Fact label="Mode">{d.mode === "ODL" ? "Distance (ODL)" : d.mode}</Fact> : null}
              {d.duration_months ? (
                <Fact label="Duration" note={d.duration_source === "fee_schedule" ? EXPLAINERS.duration_fee_schedule : EXPLAINERS.duration_eligibility_text}>
                  {formatDuration(d.duration_months)}
                </Fact>
              ) : null}
              {d.format ? <Fact label="Format">{FORMAT_LABEL[d.format]}</Fact> : null}
              {d.entrance_exam !== undefined && d.entrance_exam !== null ? <Fact label="Entrance exam">{d.entrance_exam ? "Required" : "Not required"}</Fact> : null}
              {d.min_qualification ? (
                <Fact label="Minimum qualification" note={d.min_pct_general ? `${d.min_pct_general}% marks${d.min_pct_reserved ? ` (${d.min_pct_reserved}% reserved categories)` : ""}` : undefined}>
                  {MIN_QUALIFICATION_LABEL[d.min_qualification] ?? d.min_qualification}
                </Fact>
              ) : null}
              {d.work_exp_years ? <Fact label="Work experience">{d.work_exp_years}+ years</Fact> : null}
            </dl>
            {attrs.length ? (
              <div className="mt-2 flex flex-wrap gap-1.5">
                {attrs.map((a) => <Badge key={a}>{a}</Badge>)}
              </div>
            ) : null}
            {d.spec_display && d.spec_display !== d.spec_name ? (
              <p className="text-subtle mt-2 text-xs">The university lists this specialisation as “{d.spec_display}”.</p>
            ) : null}
          </section>

          {d.eligibility || d.eligibility_text ? (
            <section aria-labelledby="elig-h">
              <h3 id="elig-h" className="eyebrow mb-2 flex items-center gap-2">
                Eligibility <EligibilityBadge e={d.eligibility} />
              </h3>
              {d.eligibility_text ? (
                <details>
                  <summary className="text-muted line-clamp-3 cursor-pointer text-sm">{d.eligibility_text}</summary>
                  <p className="text-muted mt-1 text-sm whitespace-pre-line">{d.eligibility_text}</p>
                </details>
              ) : null}
            </section>
          ) : null}

          {f && (f.ugc_deb || f.naac_grade || f.naac_accredited || f.nirf || f.aicte) ? (
            <section aria-labelledby="uni-h">
              <h3 id="uni-h" className="eyebrow mb-2">About {d.university.name}</h3>
              <ul className="grid gap-3">
                {f.ugc_deb ? (
                  <li>
                    <p className="text-text flex items-center gap-2 text-sm font-medium"><BadgeCheck className="text-success size-4" aria-hidden /> {UGC_LABEL[f.ugc_deb]}</p>
                    <Explain {...EXPLAINERS.ugc_deb} />
                  </li>
                ) : null}
                {f.naac_grade || f.naac_accredited ? (
                  <li>
                    <p className="text-text flex items-center gap-2 text-sm font-medium"><BadgeCheck className="text-success size-4" aria-hidden /> {f.naac_grade ? `NAAC ${f.naac_grade}` : "NAAC accredited"}</p>
                    <Explain {...EXPLAINERS.naac} />
                  </li>
                ) : null}
                {f.nirf ? (
                  <li>
                    <p className="text-text flex items-center gap-2 text-sm font-medium">
                      <BadgeCheck className="text-success size-4" aria-hidden />
                      NIRF {f.nirf.rank ? `rank ${f.nirf.rank}` : f.nirf.band}
                      {f.nirf.category ? ` (${f.nirf.category})` : ""}
                      {f.nirf.year ? `, ${f.nirf.year}` : ""}
                    </p>
                    <Explain {...EXPLAINERS.nirf} />
                  </li>
                ) : null}
                {f.aicte ? (
                  <li>
                    <p className="text-text flex items-center gap-2 text-sm font-medium"><BadgeCheck className="text-success size-4" aria-hidden /> AICTE</p>
                    <Explain {...EXPLAINERS.aicte} />
                  </li>
                ) : null}
              </ul>
              <Link href={`/universities/${d.university.slug}`} className="text-accent mt-3 inline-flex items-center gap-1 text-sm font-medium hover:underline">
                All programmes at {d.university.name} <ArrowRight className="size-4" aria-hidden />
              </Link>
            </section>
          ) : null}

          {d.alternatives?.length ? (
            <section aria-labelledby="alt-h">
              <h3 id="alt-h" className="eyebrow mb-2">
                {d.programme_name} · {d.spec_name} at {d.alternatives.length} other {d.alternatives.length === 1 ? "university" : "universities"}
              </h3>
              <ul className="grid gap-1">
                {d.alternatives.slice(0, 8).map((a) => (
                  <li key={a.id}>
                    <button type="button" onClick={() => setOfferingParam(a.id, "replace")} className="hover:bg-surface-hover flex w-full items-center justify-between gap-3 rounded-[var(--radius-md)] px-3 py-2 text-left">
                      <span className="min-w-0">
                        <span className="text-text block truncate text-sm font-medium">{a.university.name}</span>
                        <span className="text-subtle text-xs">{a.mode === "ODL" ? "Distance (ODL)" : a.mode}{a.naac_grade ? ` · NAAC ${a.naac_grade}` : ""}</span>
                      </span>
                      <span className="tabular text-text shrink-0 text-sm">{a.fee.total ? formatInr(a.fee.total) : "On request"}</span>
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          ) : null}

          <section id="apply" aria-labelledby="apply-h" className="glass scroll-mt-4 rounded-[var(--radius-xl)] p-4">
            <h3 id="apply-h" className="font-display text-text text-lg font-semibold">Apply or ask a question</h3>
            <p className="text-muted mt-1 text-sm">A counsellor will help you check eligibility, fees and the next intake.</p>
            <div className="mt-3 flex flex-wrap gap-2">
              <AskWitty enabled={advisorEnabled} whatsapp={whatsapp} question={`${d.programme_name} ${d.spec_name} at ${d.university.name}`} variant="primary">
                {advisorEnabled ? "Ask Witty about this programme" : "Talk to a counsellor"}
              </AskWitty>
            </div>
          </section>

          {d.verified_at ? (
            <p className="text-subtle flex items-center gap-1.5 text-xs">
              <CalendarCheck className="size-3.5" aria-hidden /> Data last verified: {formatDate(d.verified_at)}
            </p>
          ) : null}
        </div>
      ) : null}
    </Panel>
  );
}
