import { ArrowRight, Ban, CircleCheck, CircleDashed, FlaskConical, Scale } from "lucide-react";
import { Badge } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { inr } from "@/lib/programmes";
import { MODE_LABEL, REASON_LABEL, segmentLabel, type Decision } from "@/lib/routing";

function Chip({ label, value }: { label: string; value: string | null | undefined }) {
  return (
    <span className="inline-flex items-center gap-1 rounded-md border border-border bg-surface-2 px-2 py-0.5 text-[12px]">
      <span className="text-subtle">{label}</span> <span className="text-fg">{value || "any"}</span>
    </span>
  );
}

/** "Why this partner": the outcome, the lead's interest, every candidate with its numbers, exclusions and rules. */
export function DecisionView({ d }: { d: Decision }) {
  const toPartner = d.destination === "partner";
  return (
    <div className="space-y-5">
      <div className={cn("flex flex-wrap items-center gap-3 rounded-[var(--radius-card)] border px-4 py-3",
        toPartner ? "border-success/25 bg-success-bg" : "border-warning/25 bg-warning-bg")}>
        {toPartner ? <CircleCheck className="size-5 text-success" /> : <Ban className="size-5 text-warning" />}
        <div className="min-w-0 flex-1">
          <p className={cn("text-[14px] font-semibold", toPartner ? "text-success" : "text-warning")}>
            {toPartner ? <>Goes to {d.partner_name}</> : <>Goes to Eduwit&apos;s B2C CRM</>}
            {d.reference && <span className="ml-2 font-mono text-[12px] font-normal">{d.reference}</span>}
          </p>
          <p className="text-[12.5px] text-muted">
            {toPartner
              ? <>{MODE_LABEL[d.mode] ?? d.mode}{d.cpe !== null ? <> · commission {inr(d.cpe)} net of GST</> : " · no confirmed commission rate"}{d.selection_probability < 1 && ` · chosen with probability ${Math.round(d.selection_probability * 100)}%`}</>
              : REASON_LABEL[d.reason ?? ""] ?? d.reason}
          </p>
        </div>
        <div className="flex flex-wrap gap-1.5">
          {d.is_test && <Badge tone="brand"><FlaskConical className="size-3" /> Test lead: partner sandboxes only</Badge>}
          {d.committed ? <Badge tone="success">Routed</Badge> : <Badge>Simulation: nothing was sent</Badge>}
          {d.already_routed && !d.committed && <Badge tone="warning">Already routed</Badge>}
        </div>
      </div>

      <div>
        <h4 className="mb-1.5 text-[11px] font-medium uppercase tracking-wider text-subtle">Interest</h4>
        <div className="flex flex-wrap gap-1.5">
          <Chip label="Course" value={d.interest.course_key?.toUpperCase()} />
          <Chip label="Specialization" value={d.interest.specialization} />
          <Chip label="Level" value={d.interest.level} />
          <Chip label="Mode" value={d.interest.mode} />
          <Chip label="University" value={d.interest.university_id ? (d.interest.university_text ?? `#${d.interest.university_id}`) : null} />
          <Chip label="Segment" value={segmentLabel(d.interest.segment)} />
        </div>
        {!d.readiness.ready && (
          <p className="mt-2 text-[12.5px] text-warning">Not ready for automatic routing: {d.readiness.missing.join(", ")}.</p>
        )}
      </div>

      {d.candidates.length > 0 && (
        <div>
          <h4 className="mb-1.5 text-[11px] font-medium uppercase tracking-wider text-subtle">Candidates</h4>
          <div className="overflow-x-auto rounded-lg border border-border">
            <table className="w-full min-w-[640px] text-left text-[12.5px]">
              <thead className="bg-surface-2 text-[11px] uppercase tracking-wider text-subtle">
                <tr>
                  <th scope="col" className="px-3 py-2 font-medium">Partner</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">Matching programmes</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">Commission (net)</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">Today / cap</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">Leads in segment</th>
                  <th scope="col" className="px-3 py-2 font-medium">Result</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {[...d.candidates].sort((a, b) => (b.cpe ?? -1) - (a.cpe ?? -1)).map((c) => {
                  const won = toPartner && c.partner_id === d.partner_id;
                  const why = d.excluded.find((x) => Number(x.partner_id) === c.partner_id)?.why;
                  return (
                    <tr key={c.partner_id} className={cn(won && "bg-success-bg/60")}>
                      <td className="px-3 py-2 font-medium text-fg">{won && <ArrowRight className="mr-1 inline size-3.5 text-success" />}{c.name}</td>
                      <td className="tabular px-3 py-2 text-right text-muted">{c.offers}</td>
                      <td className="tabular px-3 py-2 text-right text-fg">{c.has_rate ? inr(c.cpe) : <span className="text-warning">No rate</span>}</td>
                      <td className="tabular px-3 py-2 text-right text-muted">{c.leads_today} / {c.daily_cap ?? "∞"}</td>
                      <td className="tabular px-3 py-2 text-right text-muted">{c.segment_leads}</td>
                      <td className="px-3 py-2 text-muted">{won ? <span className="font-medium text-success">Chosen</span> : why ?? (c.eligible ? "Eligible, lower commission" : "—")}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {d.rules.length > 0 && (
        <div>
          <h4 className="mb-1.5 text-[11px] font-medium uppercase tracking-wider text-subtle">Rules applied</h4>
          <ul className="space-y-1 text-[12.5px]">
            {d.rules.map((r) => <li key={r.id} className="flex items-center gap-2"><Scale className="size-3.5 text-subtle" /> <span className="text-fg">{r.name}</span> <span className="text-subtle">· {r.effect}</span></li>)}
          </ul>
        </div>
      )}

      {toPartner && d.draw !== null && (
        <p className="flex items-center gap-1.5 text-[12px] text-subtle">
          <CircleDashed className="size-3.5" /> Exploration draw {d.draw.toFixed(3)} against a {Math.round(d.exploration_share * 100)}% lane
          {d.mode === "exploration" ? ": the lead went to an under-sampled partner so its conversion can be learned." : ": the highest commission won."}
        </p>
      )}
    </div>
  );
}
