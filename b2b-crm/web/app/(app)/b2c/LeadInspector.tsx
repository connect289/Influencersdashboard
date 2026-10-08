"use client";
import { useState } from "react";
import Link from "next/link";
import { LoaderCircle, RefreshCw, Search } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import { formatDateTime } from "@/lib/format";
import { CONTRACT_VERSION, actorText, describeActivity, describeChanges, describeProvider, eventLabel, recordSummary, type LinkLead } from "@/lib/b2c-link";
import { inspectLead, resync } from "./actions";

const field = "h-9 w-40 rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";
const TONE: Record<string, "success" | "info" | "warning" | "danger" | "neutral"> = {
  delivered: "success", sending: "info", pending: "neutral", failed: "warning", dead: "danger", cancelled: "neutral",
  applied: "success", unchanged: "neutral", conflict: "warning", rejected: "danger",
};

function Section({ title, tone, children }: { title: string; tone?: "danger" | "warning" | "success"; children: React.ReactNode }) {
  return (
    <div className={cn("min-w-0 rounded-lg border p-3 text-[12.5px]", tone === "danger" ? "border-danger/30" : tone === "warning" ? "border-warning/30" : tone === "success" ? "border-success/30" : "border-border")}>
      <p className="mb-1.5 text-[12px] font-medium text-muted">{title}</p>
      <div className="space-y-1">{children}</div>
    </div>
  );
}

/** The version-3 facts the B2C CRM acts on, in words, above the raw record. */
function RecordFacts({ res }: { res: LinkLead }) {
  const s = recordSummary(res.record);
  const destination = res.record.allocation?.destination ?? null;
  return (
    <>
      {s.version < CONTRACT_VERSION && (
        <Notice tone="warning">This record is still at contract version {s.version}: the database does not build version {CONTRACT_VERSION} records yet
          (m31j_a3_b2c_contract not applied), so the sections below stay empty.</Notice>
      )}
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        <Section title="Partner bar (R2)" tone={s.bar ? "danger" : undefined}>
          {s.bar ? (
            <>
              <p className="font-medium text-danger">{s.bar.label}{s.bar.since ? ` · since ${formatDateTime(s.bar.since)}` : ""}</p>
              <p className="text-muted">Never to partners again: the B2C CRM hides its route-to-partners action and the API answers 422 <code className="font-mono">partner_barred</code>.</p>
            </>
          ) : <p className="text-muted">Not barred. Route-to-partners stays open while B2C holds the lead and consent is given.</p>}
        </Section>

        <Section title="Already with other providers (badge)">
          {s.providers.length === 0 ? <p className="text-muted">None: no partner proved it already had this student.</p> : (
            <ul className="space-y-1">
              {s.providers.map((p) => <li key={`${p.partner_id}-${p.claimed_at ?? ""}`} className="text-fg">{describeProvider(p, formatDateTime)}</li>)}
            </ul>
          )}
        </Section>

        <Section title="Hold and handling">
          {s.hold ? (
            <dl className="grid grid-cols-[auto_minmax(0,1fr)] gap-x-3 gap-y-0.5">
              <dt className="text-subtle">Hold</dt>
              <dd className="text-fg">{s.hold.label}{s.hold.open ? "" : " · closed"}{s.hold.lane ? ` · ${s.hold.lane} lane` : ""}</dd>
              <dt className="text-subtle">Why</dt>
              <dd className="text-fg">{s.handling?.reason ?? (s.hold.reason ? s.hold.reason.replace(/_/g, " ") : "—")}</dd>
              {s.handling && (
                <>
                  <dt className="text-subtle">Job</dt><dd className="text-fg">{s.handling.job ?? "—"}</dd>
                  <dt className="text-subtle">Assign</dt><dd className="text-fg">{s.handling.assignment ?? "—"}</dd>
                  <dt className="text-subtle">Script</dt><dd className="text-fg">{s.handling.script ?? "—"}</dd>
                  {s.handling.nurture_first_message_at && <><dt className="text-subtle">First message</dt><dd className="text-fg">not before {formatDateTime(s.handling.nurture_first_message_at)}</dd></>}
                </>
              )}
            </dl>
          ) : <p className="text-muted">B2C does not hold this lead{destination === "partner" ? ": it is with a partner" : destination ? "" : ": it is not routed yet"}.</p>}
          {s.actions.length > 0 && (
            <ul className="mt-1 space-y-0.5">
              {s.actions.map((a) => <li key={a.code} className="text-fg"><span className="font-medium">Asked of B2C:</span> {a.label}</li>)}
            </ul>
          )}
        </Section>

        <Section title="Partner-sharing consent" tone={s.consent.given ? "success" : s.consent.state === "refused" || s.consent.state === "withdrawn" ? "warning" : undefined}>
          <p className={cn("font-medium", s.consent.given ? "text-success" : "text-fg")}>{s.consent.label}</p>
          {s.consent.request ? (
            <p className="text-muted">Request #{s.consent.request.id}: {s.consent.requestText}
              {s.consent.request.expires_at && !s.consent.request.answer ? ` · expires ${formatDateTime(s.consent.request.expires_at)}` : ""}</p>
          ) : <p className="text-muted">No consent request in this enquiry.</p>}
        </Section>

        <Section title="Qualification">
          <p className="font-medium text-fg">{s.qualification.label ?? "—"}</p>
          {s.qualification.missing.length > 0
            ? <p className="text-muted">Missing: {s.qualification.missing.map((m) => m.label).join(", ")}.</p>
            : <p className="text-muted">Nothing missing.</p>}
        </Section>

        <Section title="Other courses asked about">
          {s.other_courses.length === 0
            ? <p className="text-muted">None. The B2C CRM may write <code className="font-mono">interest.other_courses</code> (up to 9) while it holds the lead.</p>
            : <div className="flex flex-wrap gap-1">{s.other_courses.map((c, i) => <Badge key={`${c}-${i}`}>{c}</Badge>)}</div>}
        </Section>
      </div>
    </>
  );
}

/** One lead as the B2C CRM sees it: the version-3 facts, the record, its versions and deliveries, and what the B2C CRM wrote. */
export function LeadInspector({ initial }: { initial: number | null }) {
  const [id, setId] = useState(initial ? String(initial) : "");
  const [res, setRes] = useState<LinkLead | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<"check" | "resend" | null>(null);

  const load = async () => {
    setBusy("check"); setError(null);
    try { const r = await inspectLead(Number(id)); if (r.ok) setRes(r.data); else { setRes(null); setError(r.error); } } finally { setBusy(null); }
  };
  const resend = async () => {
    setBusy("resend");
    try {
      const r = await resync(Number(id));
      if (!r.ok) { toast.error(r.error); return; }
      toast.success("Sent again as a new version");
      const x = await inspectLead(Number(id)); if (x.ok) setRes(x.data);
    } finally { setBusy(null); }
  };

  const version = res ? recordSummary(res.record).version : null;

  return (
    <div className="space-y-4 p-5">
      <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void load(); }}>
        <label className="space-y-1"><span className="block text-[13px] font-medium text-fg">Lead number</span>
          <input className={field} inputMode="numeric" value={id} placeholder="e.g. 1342" onChange={(e) => setId(e.target.value.replace(/\D/g, ""))} /></label>
        <Button type="submit" disabled={!id || Boolean(busy)}>{busy === "check" ? <LoaderCircle className="size-4 animate-spin" /> : <Search className="size-4" />} Inspect</Button>
        {res && <Button variant="secondary" disabled={Boolean(busy)} onClick={() => void resend()}>{busy === "resend" ? <LoaderCircle className="size-4 animate-spin" /> : <RefreshCw className="size-4" />} Send again</Button>}
      </form>
      {error && <Notice tone="error">{error}</Notice>}
      {res && (
        <>
          <div className="flex flex-wrap items-center gap-2 text-[13px]">
            <Link href={`/leads?lead=${res.lead_id}`} className="font-medium text-fg hover:underline">{res.name ?? `Lead #${res.lead_id}`}</Link>
            {res.record.is_test && <Badge tone="warning">Test lead</Badge>}
            {res.held_by_b2c ? <Badge tone="success">Held by B2C</Badge> : <Badge>Not held by B2C</Badge>}
            {res.shared ? <Badge tone="info">In the B2C CRM&apos;s copy · version {res.version}</Badge> : <Badge>Not in the B2C CRM&apos;s copy</Badge>}
            {version !== null && <Badge tone={version >= CONTRACT_VERSION ? "brand" : "warning"}>Contract version {version}</Badge>}
            {res.changed_at && <span className="text-muted">last sent {formatDateTime(res.changed_at)}{res.origin ? ` (${res.origin})` : ""}</span>}
          </div>
          <RecordFacts res={res} />
          <div className="grid gap-4 xl:grid-cols-[1.2fr_1fr]">
            <div className="min-w-0">
              <p className="mb-1.5 text-[12px] font-medium text-muted">Record as the B2C CRM receives it</p>
              <pre className="max-h-[520px] overflow-auto rounded-lg border border-border bg-surface-2 p-3 font-mono text-[11.5px] text-fg">{JSON.stringify(res.record, null, 2)}</pre>
            </div>
            <div className="min-w-0 space-y-4">
              <div>
                <p className="mb-1.5 text-[12px] font-medium text-muted">Deliveries</p>
                {res.deliveries.length === 0 ? <p className="text-[12.5px] text-subtle">None: the endpoint is off, the lead was never shared, or its changes went out in a batch.</p> : (
                  <ul className="divide-y divide-border rounded-lg border border-border text-[12.5px]">
                    {res.deliveries.map((d) => (
                      <li key={d.id} className="flex flex-wrap items-center gap-2 px-3 py-2">
                        <span className="text-fg">v{d.version}</span><span className="text-muted">{eventLabel(d.type)}</span>
                        <Badge tone={TONE[d.status] ?? "neutral"}>{d.status}</Badge>
                        <span className="ml-auto text-subtle">{formatDateTime(d.delivered_at ?? d.created_at)}</span>
                        {d.error && <span className="w-full truncate text-[11.5px] text-danger" title={d.error}>{d.error}</span>}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
              <div>
                <p className="mb-1.5 text-[12px] font-medium text-muted">Written by the B2C CRM</p>
                {res.writes.length === 0 ? <p className="text-[12.5px] text-subtle">Nothing yet.</p> : (
                  <ul className="divide-y divide-border rounded-lg border border-border text-[12.5px]">
                    {res.writes.map((w, i) => (
                      <li key={i} className="space-y-0.5 px-3 py-2">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="font-medium text-fg">{w.kind === "activity" ? "Activity" : "Update"}</span>
                          <Badge tone={TONE[w.status] ?? "neutral"}>{w.status}</Badge>
                          <span className="text-muted">{actorText(w.actor)}</span>
                          <span className="ml-auto text-subtle">{formatDateTime(w.at)}</span>
                        </div>
                        <p className="truncate text-muted" title={JSON.stringify(w.changes)}>{w.error ?? (w.kind === "activity" ? describeActivity(w.changes) : describeChanges(w.changes))}</p>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
