"use client";
import { useState } from "react";
import Link from "next/link";
import { Check, LoaderCircle, Search, X } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { Notice } from "@/components/ui/Notice";
import { formatDateTime } from "@/lib/format";
import { EVENT_STATUS, MATCH_KEY_LABEL, STAGE_LABEL, formatInr, type LeadCheck as Check_ } from "@/lib/capi";
import { checkLead } from "./actions";

const field = "h-9 w-40 rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";

function Yes({ ok, children }: { ok: boolean; children: React.ReactNode }) {
  return <span className="flex items-center gap-1.5">{ok ? <Check className="size-3.5 text-success" /> : <X className="size-3.5 text-danger" />}{children}</span>;
}

/** One lead: its ad identifiers, consent, milestones and the event each platform would get. For checking a setup with a test lead. */
export function LeadCheck({ initial }: { initial: number | null }) {
  const [id, setId] = useState(initial ? String(initial) : "");
  const [res, setRes] = useState<Check_ | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<"check" | "write" | null>(null);
  const [open, setOpen] = useState<string | null>(null);

  const run = async (write: boolean) => {
    setBusy(write ? "write" : "check"); setError(null);
    try {
      const r = await checkLead(Number(id), write);
      if (!r.ok) { setError(r.error); setRes(null); return; }
      setRes(r.data);
      if (write) toast.success(r.data.written ? `${r.data.written} events logged` : "Nothing new to log");
    } finally { setBusy(null); }
  };

  const consentOk = res ? !res.consent.opted_out && (res.consent.rule === "sales" ? Boolean(res.consent.sales_at) : Boolean(res.consent.marketing_at)) : false;
  return (
    <div className="space-y-4 p-5">
      <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void run(false); }}>
        <label className="space-y-1">
          <span className="block text-[13px] font-medium text-fg">Lead number</span>
          <input className={field} inputMode="numeric" value={id} placeholder="e.g. 1342" onChange={(e) => setId(e.target.value.replace(/\D/g, ""))} />
        </label>
        <Button type="submit" disabled={!id || Boolean(busy)}>{busy === "check" ? <LoaderCircle className="size-4 animate-spin" /> : <Search className="size-4" />} Check</Button>
        {res && <Button variant="secondary" disabled={Boolean(busy)} onClick={() => void run(true)}>{busy === "write" && <LoaderCircle className="size-4 animate-spin" />} Log these events now</Button>}
      </form>
      {error && <Notice tone="error">{error}</Notice>}
      {res && (
        <>
          <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
            <div className="rounded-lg border border-border p-3 text-[12.5px]">
              <p className="mb-1.5 font-medium text-fg"><Link href={`/leads?lead=${res.lead.id}`} className="hover:underline">{res.lead.name ?? `Lead #${res.lead.id}`}</Link>
                {res.lead.is_test && <Badge tone="brand" className="ml-1.5">test: never sent</Badge>}</p>
              <p className="text-muted">Cycle {res.lead.cycle_no}{res.lead.deleted && " · deleted"}</p>
            </div>
            <div className="rounded-lg border border-border p-3 text-[12.5px]">
              <p className="mb-1.5 flex flex-wrap items-center gap-1.5 font-medium text-fg">Campaign
                {res.campaign.paid ? <Badge tone="success">Paid · {res.campaign.platform === "meta" ? "Meta" : res.campaign.platform === "google" ? "Google" : "other"}</Badge>
                  : <Badge>{res.campaign.platform === "none" ? "No ad" : "Organic or unknown"}</Badge>}</p>
              {res.campaign.campaign_name || res.campaign.campaign_id || res.campaign.utm?.campaign ? (
                <ul className="space-y-0.5 text-muted">
                  <li className="text-fg">{res.campaign.campaign_name ?? res.campaign.utm?.campaign ?? `Campaign ${res.campaign.campaign_id}`}</li>
                  {res.campaign.campaign_id && <li>ID <span className="font-mono text-[11.5px]">{res.campaign.campaign_id}</span></li>}
                  {(res.campaign.adset_name || res.campaign.adset_id) && <li>Ad set {res.campaign.adset_name ?? res.campaign.adset_id}</li>}
                  {(res.campaign.ad_name || res.campaign.ad_id) && <li>Ad {res.campaign.ad_name ?? res.campaign.ad_id}</li>}
                </ul>
              ) : <p className="text-muted">No campaign recorded.</p>}
              {!res.campaign.paid && <p className="mt-1 text-warning">Not from a paid ad: nothing is reported.</p>}
              {res.campaign.paid && !res.campaign.matchable && <p className="mt-1 text-warning">UTM tags only: the platform cannot match it, so nothing is reported.</p>}
            </div>
            <div className="rounded-lg border border-border p-3 text-[12.5px]">
              <p className="mb-1.5 font-medium text-fg">Ad identifiers</p>
              {Object.keys(res.ids).length === 0 ? <p className="text-danger">None: this lead makes no events.</p>
                : <ul className="space-y-0.5 text-muted">{Object.entries(res.ids).map(([k, v]) => <li key={k}><span className="text-fg">{k}</span> <span className="font-mono text-[11.5px]">{v.length > 28 ? v.slice(0, 28) + "…" : v}</span></li>)}</ul>}
            </div>
            <div className="space-y-1 rounded-lg border border-border p-3 text-[12.5px] text-muted">
              <p className="font-medium text-fg">Consent (rule: {res.consent.rule})</p>
              <Yes ok={Boolean(res.consent.sales_at)}>Contact {res.consent.sales_at && <span className="text-subtle">{formatDateTime(res.consent.sales_at)}</span>}</Yes>
              <Yes ok={Boolean(res.consent.marketing_at)}>Marketing {res.consent.marketing_at && <span className="text-subtle">{formatDateTime(res.consent.marketing_at)}</span>}</Yes>
              {res.consent.opted_out && <Yes ok={false}>Opted out</Yes>}
              {!consentOk && <p className="text-warning">Events are logged as skipped until the consent arrives.</p>}
            </div>
          </div>
          <div className="overflow-x-auto rounded-lg border border-border">
            <table className="w-full min-w-[720px] text-left text-[12.5px]">
              <thead className="bg-surface-2/60 text-[11px] uppercase tracking-wider text-subtle">
                <tr><th scope="col" className="px-3 py-2 font-medium">Milestone</th><th scope="col" className="px-3 py-2 font-medium">When</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">Value</th><th scope="col" className="px-3 py-2 font-medium">Meta</th><th scope="col" className="px-3 py-2 font-medium">Google</th></tr>
              </thead>
              <tbody className="divide-y divide-border">
                {res.milestones.map((m) => (
                  <tr key={m.stage} className="align-top">
                    <td className="px-3 py-2 font-medium text-fg">{STAGE_LABEL[m.stage]?.label ?? m.stage}</td>
                    <td className="whitespace-nowrap px-3 py-2 text-muted">{formatDateTime(m.at)}</td>
                    <td className="tabular px-3 py-2 text-right">{formatInr(m.value_inr)}</td>
                    {(["meta", "google"] as const).map((p) => {
                      const ev = m[p];
                      const logged = res.events.find((e) => e.platform === p && e.stage === m.stage);
                      const key = `${m.stage}.${p}`;
                      return (
                        <td key={p} className="px-3 py-2">
                          {ev ? (
                            <>
                              <span className="text-fg">{p === "meta" ? ev.name : "Conversion"}</span>
                              <span className="block text-[11.5px] text-subtle">{ev.match_keys.map((k) => MATCH_KEY_LABEL[k] ?? k).join(", ")}</span>
                              {logged && <Badge tone={EVENT_STATUS[logged.status]?.tone ?? "neutral"} className="mt-1">{EVENT_STATUS[logged.status]?.label ?? logged.status}</Badge>}
                              <button type="button" className="ml-1.5 text-[11.5px] text-info hover:underline" onClick={() => setOpen(open === key ? null : key)}>{open === key ? "Hide" : "Payload"}</button>
                              {open === key && <pre className="mt-1.5 max-h-56 max-w-sm overflow-auto rounded bg-surface-2 p-2 font-mono text-[11px] text-fg">{JSON.stringify(ev.payload, null, 2)}</pre>}
                            </>
                          ) : <span className="text-subtle">{!res.campaign.paid || !res.campaign.matchable ? "Not a paid, matchable lead" : res.campaign.platform !== p ? "—" : "Off for this signal"}</span>}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="text-[12px] text-muted">The payload is exactly what is sent: email and phone appear only as SHA-256 hashes. Google&apos;s conversion action is added when the event is sent.</p>
        </>
      )}
    </div>
  );
}
