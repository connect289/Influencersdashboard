import Link from "next/link";
import { CircleCheck, CircleDashed, Radio, Send } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { siteUrl } from "@/lib/env";
import { formatDateTime, relativeTime } from "@/lib/format";
import { ALLOCATION_LABEL } from "@/lib/routing";
import { EVENT_STATUS_LABEL, pushOutcomeText, type PartnerConnection } from "@/lib/push";
import { ADAPTER_LABEL, holdWindowText, type Partner } from "@/lib/partners";
import { partnerDetail } from "@/lib/partners-data";
import { adapterHoldMinutes, withDedupe, type AdapterStatus } from "@/lib/adapters";
import { CredentialsForm, DisputeList, SigningSecret } from "./ConnectionControls";
import { AdapterPanel } from "./AdapterPanel";

function Step({ done, children }: { done: boolean; children: React.ReactNode }) {
  return (
    <li className="flex items-start gap-2.5 text-[13px]">
      {done ? <CircleCheck className="mt-0.5 size-4 shrink-0 text-success" /> : <CircleDashed className="mt-0.5 size-4 shrink-0 text-subtle" />}
      <span className={done ? "text-fg" : "text-muted"}>{children}</span>
    </li>
  );
}

/**
 * How Eduwit talks to the partner's CRM (spec B8.1) and how the partner talks back (B8.2), with Addendum 3's duplicate handling
 * (D37: a CRM adapter gets the 0-minute hold only once the Admin confirms it blocks duplicates on create) and the commission
 * disputes of both kinds (PART 5.8, PART 6.1). The partner row comes from partner_detail, memoised per request with the page's read.
 */
export async function ConnectionTab({ id, c, adapter, partner }: { id: number; c: PartnerConnection; adapter?: AdapterStatus | null; partner?: Partner | null }) {
  const p = partner ?? (await partnerDetail(id))?.partner ?? null;
  const s = adapter ? withDedupe(adapter, p) : null;
  const events = `${siteUrl()}${c.events_url_path}`;
  const push = c.push;
  const statuses = Object.entries(push.by_status).sort((a, b) => b[1] - a[1]);
  const lostInGrace = push.lost_in_grace ?? 0;
  const dedupeSettled = p ? p.dedupe_mode !== "sync" || Boolean(p.dedupe_confirmed_at) : true;
  const holdText = p ? holdWindowText(p) : `${adapterHoldMinutes(s?.dedupe_confirmed)} min`;
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <Card className="min-w-0 xl:self-start">
        <CardHeader title="Setup" description={s?.adapter === "inhouse"
          ? "The partner's own CRM: Eduwit sends each lead to its create-lead address, reads the answer for the record ID or a duplicate, and reads status back from its changed-leads address, a webhook to the events address, or its export. See docs/partner-adapters.md."
          : s
          ? `${s.spec.label} adapter: Eduwit creates the lead through ${s.spec.label}'s own API${s.spec.poll ? " and reads stage changes back by polling or webhook" : ""}. See docs/partner-adapters.md.`
          : `${ADAPTER_LABEL[c.adapter_type as keyof typeof ADAPTER_LABEL] ?? c.adapter_type}. Pushes follow the generic contract in docs/partner-api.md.`} />
        <ul className="space-y-2 px-5 py-4">
          {s ? (<>
            <Step done={s.envs.sandbox.configured}>Sandbox connection set up (a test org or account)</Step>
            <Step done={s.envs.live.configured}>Live connection set up</Step>
            <Step done={dedupeSettled}>
              Duplicate handling settled: hold window {holdText}
              {!dedupeSettled && <> · tick &lsquo;This CRM blocks duplicates on create&rsquo; below, or save without it for the 30-minute hold</>}
            </Step>
          </>) : (<>
          <Step done={Boolean(c.test_endpoint)}>Sandbox endpoint {c.test_endpoint ? <span className="break-all font-mono text-[12px]">{c.test_endpoint}</span> : <Link href="?tab=settings" className="text-info hover:underline">set it in Settings</Link>}</Step>
          <Step done={Boolean(c.api_base_url)}>Live endpoint {c.api_base_url ? <span className="break-all font-mono text-[12px]">{c.api_base_url}</span> : <Link href="?tab=settings" className="text-info hover:underline">set it in Settings</Link>}</Step>
          <Step done={c.has_token || c.auth_type === "none"}>API credential stored</Step>
          {p && <Step done={dedupeSettled}>Duplicate handling settled: hold window {holdText}{!dedupeSettled && <> · <Link href="?tab=settings" className="text-info hover:underline">confirm it in Settings</Link></>}</Step>}
          </>)}
          <Step done={c.has_inbound_secret}>Signing secret shared with the partner</Step>
          <Step done={c.test_accepted}>A test lead accepted by the partner&apos;s sandbox</Step>
        </ul>
        <div className="border-t border-border px-5 py-3 text-[12.5px] text-muted">
          The partner sends events to <span className="break-all font-mono text-fg">{events}</span>
        </div>
      </Card>

      <div className="min-w-0 space-y-6">
        {s ? (
          <Card className="min-w-0">
            <CardHeader title={`${s.spec.label} connection`} description="Credentials go to the vault and are never shown again. Live and sandbox are kept apart; the duplicate-blocking confirmation is one answer for both." />
            <AdapterPanel id={id} s={s} />
          </Card>
        ) : (
          <Card className="min-w-0">
            <CardHeader title="API credential" />
            <CredentialsForm id={id} authType={c.auth_type} header={c.auth_header} hasToken={c.has_token} />
          </Card>
        )}
        <Card className="min-w-0">
          <CardHeader title="Signing secret" description="HMAC-SHA256 over timestamp.body, both ways." />
          <SigningSecret id={id} has={c.has_inbound_secret} />
        </Card>
      </div>

      <Card className="min-w-0 xl:col-span-2">
        <CardHeader title="Pushes" description={`Last 30 days by status${push.duplicate_rate_7d !== null ? ` · duplicate rate this week ${Math.round(push.duplicate_rate_7d * 100)}%` : ""}. Hold window ${holdText}: a duplicate or rejection inside it moves the lead on. Retries: 10 s, 1 min, 5 min, 15 min, 40 min; then the lead goes to another partner.`} />
        {(statuses.length > 0 || lostInGrace > 0) && (
          <div className="flex flex-wrap gap-1.5 px-5 pt-4">
            {statuses.map(([k, n]) => <Badge key={k} tone={k === "accepted" ? "success" : k === "failed" || k === "rejected" ? "danger" : k === "duplicate" ? "warning" : "neutral"}>{ALLOCATION_LABEL[k] ?? k} <span className="tabular">{n}</span></Badge>)}
            {lostInGrace > 0 && <span title="Marked lost by the partner; back with the partner on new activity, to B2C nurture after 7 days"><Badge tone="danger">Lost, in grace <span className="tabular">{lostInGrace}</span></Badge></span>}
          </div>
        )}
        {push.retrying.length > 0 && (
          <ul className="space-y-1 px-5 pt-3 text-[12.5px]">
            {push.retrying.map((r) => (
              <li key={r.id} className="text-warning">
                <span className="font-mono">{r.reference}</span> · attempt {r.attempts} failed ({r.last_error}) · next try {r.next_push_at ? relativeTime(r.next_push_at) : "soon"}
              </li>
            ))}
          </ul>
        )}
        {push.requests.length === 0 ? (
          <EmptyState icon={Send} title="No pushes yet">Route a test lead from Routing → Simulate to try the sandbox.</EmptyState>
        ) : (
          <div className="relative mt-3 overflow-x-auto">
            <table className="w-full min-w-[720px] text-left text-[12.5px]">
              <thead className="text-[11px] uppercase tracking-wider text-subtle">
                <tr className="border-y border-border">
                  <th scope="col" className="px-5 py-2 font-medium">Sent</th>
                  <th scope="col" className="px-3 py-2 font-medium">Lead</th>
                  <th scope="col" className="px-3 py-2 font-medium">Attempt</th>
                  <th scope="col" className="px-3 py-2 font-medium">Endpoint</th>
                  <th scope="col" className="px-3 py-2 font-medium">HTTP</th>
                  <th scope="col" className="px-5 py-2 font-medium">Result</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {push.requests.map((q) => (
                  <tr key={q.id}>
                    <td className="whitespace-nowrap px-5 py-2 text-muted" title={formatDateTime(q.sent_at)}>{relativeTime(q.sent_at)}</td>
                    <td className="px-3 py-2 font-mono text-fg">{q.reference}</td>
                    <td className="tabular px-3 py-2 text-muted">{q.attempt}</td>
                    <td className="px-3 py-2">{q.sandbox ? <Badge tone="brand">Sandbox</Badge> : <Badge>Live</Badge>}</td>
                    <td className="tabular px-3 py-2 text-muted">{q.status_code ?? "—"}</td>
                    <td className={cn("px-5 py-2", q.outcome === "created" ? "text-success" : q.outcome === "duplicate" && q.claim_proof_ok === false ? "text-danger" : q.outcome ? "text-warning" : "text-subtle")}>
                      {pushOutcomeText(q)}{q.error && <span className="ml-1 text-subtle">· {q.error}</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card className="min-w-0">
        <CardHeader title="Events from the partner" description="Stored raw first, then applied. Types beyond duplicate, rejected, contacted, stage and lost wait for the mapping studio." />
        {push.events.length === 0 ? (
          <EmptyState icon={Radio} title="No events yet">They appear here as the partner reports duplicates, contacts, stages and losses.</EmptyState>
        ) : (
          <ul className="divide-y divide-border">
            {push.events.map((e) => (
              <li key={e.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-2.5 text-[12.5px]">
                <Badge>{e.event_type}</Badge>
                <span className="font-mono text-fg">{e.reference ?? "—"}</span>
                <span className={cn(e.status === "error" ? "text-danger" : e.status === "applied" ? "text-success" : "text-muted")}>{EVENT_STATUS_LABEL[e.status] ?? e.status}</span>
                {e.result && <span className="min-w-0 truncate text-subtle">{e.result}</span>}
                <span className="ml-auto text-subtle" title={formatDateTime(e.received_at)}>{relativeTime(e.received_at)}</span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card className="min-w-0">
        <CardHeader title="Commission disputes" description="Two kinds: a duplicate claimed within 24 hours of acceptance, and activity the partner reported after a lost lead's grace ended and it moved to B2C. The lead never moves; you decide the commission." />
        {push.disputes.length === 0
          ? <EmptyState icon={CircleCheck} title="No open disputes">A duplicate claim within 24 hours of acceptance appears here with the partner&apos;s proof; so does activity or an enrolment reported after the lead left for B2C.</EmptyState>
          : <DisputeList disputes={push.disputes} />}
      </Card>
    </div>
  );
}
