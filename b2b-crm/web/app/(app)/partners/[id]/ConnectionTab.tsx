import Link from "next/link";
import { CircleCheck, CircleDashed, Radio, Send } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { siteUrl } from "@/lib/env";
import { formatDateTime, relativeTime } from "@/lib/format";
import { ALLOCATION_LABEL } from "@/lib/routing";
import { EVENT_STATUS_LABEL, PUSH_OUTCOME_LABEL, type PartnerConnection } from "@/lib/push";
import { ADAPTER_LABEL } from "@/lib/partners";
import type { AdapterStatus } from "@/lib/adapters";
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

/** How Eduwit talks to the partner's CRM (spec B8.1) and how the partner talks back (B8.2). */
export function ConnectionTab({ id, c, adapter }: { id: number; c: PartnerConnection; adapter?: AdapterStatus | null }) {
  const events = `${siteUrl()}${c.events_url_path}`;
  const push = c.push;
  const statuses = Object.entries(push.by_status).sort((a, b) => b[1] - a[1]);
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <Card className="min-w-0 xl:self-start">
        <CardHeader title="Setup" description={adapter
          ? `${adapter.spec.label} adapter: Eduwit creates the lead through ${adapter.spec.label}'s own API${adapter.spec.poll ? " and reads stage changes back by polling or webhook" : ""}. See docs/partner-adapters.md.`
          : `${ADAPTER_LABEL[c.adapter_type as keyof typeof ADAPTER_LABEL] ?? c.adapter_type}. Pushes follow the generic contract in docs/partner-api.md.`} />
        <ul className="space-y-2 px-5 py-4">
          {adapter ? (<>
            <Step done={adapter.envs.sandbox.configured}>Sandbox connection set up (a test org or account)</Step>
            <Step done={adapter.envs.live.configured}>Live connection set up</Step>
          </>) : (<>
          <Step done={Boolean(c.test_endpoint)}>Sandbox endpoint {c.test_endpoint ? <span className="break-all font-mono text-[12px]">{c.test_endpoint}</span> : <Link href="?tab=settings" className="text-info hover:underline">set it in Settings</Link>}</Step>
          <Step done={Boolean(c.api_base_url)}>Live endpoint {c.api_base_url ? <span className="break-all font-mono text-[12px]">{c.api_base_url}</span> : <Link href="?tab=settings" className="text-info hover:underline">set it in Settings</Link>}</Step>
          <Step done={c.has_token || c.auth_type === "none"}>API credential stored</Step>
          </>)}
          <Step done={c.has_inbound_secret}>Signing secret shared with the partner</Step>
          <Step done={c.test_accepted}>A test lead accepted by the partner&apos;s sandbox</Step>
        </ul>
        <div className="border-t border-border px-5 py-3 text-[12.5px] text-muted">
          The partner sends events to <span className="break-all font-mono text-fg">{events}</span>
        </div>
      </Card>

      <div className="min-w-0 space-y-6">
        {adapter ? (
          <Card className="min-w-0">
            <CardHeader title={`${adapter.spec.label} connection`} description="Credentials go to the vault and are never shown again. Live and sandbox are kept apart." />
            <AdapterPanel id={id} s={adapter} />
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
        <CardHeader title="Pushes" description={`Last 30 days by status${push.duplicate_rate_7d !== null ? ` · duplicate rate this week ${Math.round(push.duplicate_rate_7d * 100)}%` : ""}. Retries: 10 s, 1 min, 5 min, 15 min, 1 h; then the lead goes to another partner.`} />
        {statuses.length > 0 && (
          <div className="flex flex-wrap gap-1.5 px-5 pt-4">
            {statuses.map(([s, n]) => <Badge key={s} tone={s === "accepted" ? "success" : s === "failed" || s === "rejected" ? "danger" : s === "duplicate" ? "warning" : "neutral"}>{ALLOCATION_LABEL[s] ?? s} <span className="tabular">{n}</span></Badge>)}
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
                    <td className={cn("px-5 py-2", q.outcome === "created" ? "text-success" : q.outcome ? "text-warning" : "text-subtle")}>
                      {q.outcome ? PUSH_OUTCOME_LABEL[q.outcome] ?? q.outcome : "Waiting"}{q.error && <span className="ml-1 text-subtle">· {q.error}</span>}
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
        <CardHeader title="Commission disputes" description="Duplicate claims made after the student was told about this partner. The lead never moves; you decide the commission." />
        {push.disputes.length === 0
          ? <EmptyState icon={CircleCheck} title="No open disputes">A claim within the duplicate window after acceptance appears here with the partner&apos;s proof.</EmptyState>
          : <DisputeList disputes={push.disputes} />}
      </Card>
    </div>
  );
}
