"use client";

import dynamic from "next/dynamic";
import { useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { Loader2 } from "lucide-react";
import { Badge } from "@/components/ui/Badge";
import { Panel } from "@/components/ui/Panel";
import { FEE_DISCLAIMER } from "@/content/site";
import { track } from "@/lib/client/analytics";
import { setPanelParam } from "@/lib/client/use-finder";
import { formatDuration, formatInr, formatInrRange } from "@/lib/format";
import type { ProgrammeGroup, SearchResult } from "@/lib/search/types";

const ApplicationForm = dynamic(() => import("@/components/forms/ApplicationForm").then((m) => m.ApplicationForm), {
  ssr: false,
  loading: () => <p className="text-muted text-sm">Loading the form…</p>,
});

/**
 * Programme-group panel (spec 6.6): the universities offering one programme + specialisation, the fee and duration
 * ranges, and the application form with a university picker. Deep link: `?group=<programme>:<specialisations>`.
 */
export function GroupPanel({ whatsapp, goals = [] }: { whatsapp: string; goals?: { value: string; label: string }[] }) {
  const sp = useSearchParams();
  const key = sp.get("group");
  const [res, setRes] = useState<{ key: string; g: ProgrammeGroup | null } | null>(null);

  useEffect(() => {
    if (!key || !/^[a-z0-9-]+:[a-z0-9+-]+$/.test(key)) return;
    const ctrl = new AbortController();
    fetch(`/api/search?group=${encodeURIComponent(key)}&page_size=1`, { signal: ctrl.signal })
      .then((r) => r.json() as Promise<SearchResult>)
      .then((j) => {
        setRes({ key, g: (j.items as ProgrammeGroup[])[0] ?? null });
        track("panel_open", { kind: "group" });
        const [programme, specs] = key.split(":");
        track("programme_view", { programme, specialisation: specs, level: (j.items as ProgrammeGroup[])[0]?.level_id });
      })
      .catch(() => undefined);
    return () => ctrl.abort();
  }, [key]);

  const g = res?.key === key ? res.g : null;
  const loading = !!key && res?.key !== key;
  const dur = g?.duration_min && g.duration_max ? (g.duration_min === g.duration_max ? formatDuration(g.duration_min) : `${formatDuration(g.duration_min)} – ${formatDuration(g.duration_max)}`) : null;
  const items = g?.items ?? [];

  return (
    <Panel
      open={!!key}
      onOpenChange={(v) => !v && setPanelParam("group", null)}
      title={g ? `${g.programme_name} · ${g.spec_name}` : loading ? "Loading…" : "Programme not found"}
      description={g ? `${g.level_label} · ${g.universities} ${g.universities === 1 ? "university" : "universities"}` : undefined}
      footer={
        g ? (
          <button type="button" onClick={() => document.getElementById("apply-group")?.scrollIntoView({ behavior: "smooth" })} className="bg-primary text-on-primary inline-flex h-11 w-full items-center justify-center rounded-full text-sm font-semibold">
            Apply now
          </button>
        ) : null
      }
    >
      {loading ? (
        <p className="text-muted flex items-center gap-2" role="status">
          <Loader2 className="size-4 animate-spin" aria-hidden /> Loading…
        </p>
      ) : !g ? (
        <p className="text-muted">This programme is no longer listed.</p>
      ) : (
        <div className="grid gap-6">
          <div className="glass rounded-[var(--radius-xl)] p-4">
            {g.fee_min && g.fee_max ? (
              <>
                <p className="text-subtle text-xs">Total programme fee</p>
                <p className="tabular font-display text-text text-2xl font-semibold">{formatInrRange(g.fee_min, g.fee_max)}</p>
                <p className="text-amber-text mt-1 text-sm font-medium">Easy EMI available</p>
              </>
            ) : (
              <p className="text-text font-medium">Fees on request</p>
            )}
            <div className="mt-2 flex flex-wrap gap-2 text-sm">
              {dur ? <Badge>{dur}</Badge> : null}
              {g.best_naac ? <Badge tone="verified">Up to NAAC {g.best_naac}</Badge> : null}
              {g.modes.map((m) => <Badge key={m}>{m === "ODL" ? "Distance (ODL)" : m}</Badge>)}
            </div>
            <p className="text-subtle mt-2 text-xs">{FEE_DISCLAIMER}</p>
          </div>

          <section aria-labelledby="g-unis">
            <h3 id="g-unis" className="eyebrow mb-2">Universities offering it</h3>
            <ul className="grid gap-1">
              {items.map((o) => (
                <li key={o.id}>
                  <button type="button" onClick={() => setPanelParam("offering", String(o.id))} className="hover:bg-surface-hover flex w-full items-center justify-between gap-3 rounded-[var(--radius-md)] px-3 py-2 text-left">
                    <span className="min-w-0">
                      <span className="text-text block truncate text-sm font-medium">{o.university.name}</span>
                      <span className="text-subtle text-xs">
                        {o.mode === "ODL" ? "Distance (ODL)" : o.mode}
                        {o.duration_months ? ` · ${formatDuration(o.duration_months)}` : ""}
                        {o.naac_grade ? ` · NAAC ${o.naac_grade}` : ""}
                      </span>
                    </span>
                    <span className="tabular text-text shrink-0 text-sm">{o.fee.total ? formatInr(o.fee.total) : "On request"}</span>
                  </button>
                </li>
              ))}
            </ul>
          </section>

          <section id="apply-group" aria-labelledby="apply-g-h" className="glass scroll-mt-4 rounded-[var(--radius-xl)] p-4">
            <h3 id="apply-g-h" className="font-display text-text mb-4 text-lg font-semibold">Apply or get help choosing</h3>
            <ApplicationForm
              key={g.key}
              target={{
                kind: "group",
                groupKey: g.key,
                label: `${g.programme_name} ${g.spec_name}`,
                exploreHref: `/programmes?programme=${g.programme_id}`,
                universities: items.map((o) => ({ offeringId: o.id, name: `${o.university.name}${o.mode === "ODL" ? " (Distance)" : ""}`, feeTotal: o.fee.total, level: o.level_id, minQualification: o.min_qualification })),
              }}
              goals={goals}
              whatsapp={whatsapp}
            />
          </section>
        </div>
      )}
    </Panel>
  );
}
