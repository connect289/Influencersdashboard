import { ArrowRightLeft, CircleAlert, ListTodo, Mail, MessageSquare, PhoneCall, PhoneIncoming, StickyNote, Users } from "lucide-react";
import { Badge } from "@/components/ui/Card";
import { formatDateTime, relativeTime } from "@/lib/format";
import { humanize } from "@/lib/leads";
import { ACTIVITY_LABEL, SLA_LABEL, SLA_STATUS, type LeadPartnerSync } from "@/lib/sync";

const EVENT_TONE: Record<string, "success" | "neutral" | "warning" | "danger"> = { applied: "success", ignored: "neutral", held_unmapped: "warning", error: "danger", received: "neutral" };
const EVENT_STATUS: Record<string, string> = { applied: "Applied", ignored: "Ignored", held_unmapped: "Held", error: "Failed", received: "Received" };

const KIND_ICON = { call: PhoneCall, whatsapp: MessageSquare, sms: MessageSquare, email: Mail, meeting: Users, note: StickyNote, task: ListTodo, stage_change: ArrowRightLeft };

function duration(sec: number | null) {
  if (!sec) return null;
  return sec < 60 ? `${sec} s` : `${Math.floor(sec / 60)} min ${sec % 60 ? `${sec % 60} s` : ""}`.trim();
}

function H({ children }: { children: React.ReactNode }) {
  return <h3 className="mb-2 text-[11px] font-medium uppercase tracking-wider text-subtle">{children}</h3>;
}

/** What the partner reported for this lead: its sales activity, the SLA clocks, and every raw event with its mapping. */
export function PartnerSyncTab({ s }: { s: LeadPartnerSync }) {
  const open = s.slas.filter((c) => c.status === "pending" || c.status === "breached");
  return (
    <div className="divide-y divide-border">
      {s.stale_since && (
        <p className="flex items-center gap-2 bg-warning-bg px-5 py-2.5 text-[12.5px] text-warning">
          <CircleAlert className="size-4 shrink-0" /> No status update from the partner since {formatDateTime(s.stale_since)}.
        </p>
      )}

      <section className="px-5 py-4">
        <H>SLA clocks</H>
        {s.slas.length === 0 ? <p className="text-[13px] text-muted">No clocks yet: they start when the lead is pushed to a partner.</p> : (
          <ul className="space-y-1.5">
            {[...open, ...s.slas.filter((c) => !open.includes(c))].map((c) => (
              <li key={c.id} className="flex items-start justify-between gap-3 text-[13px]">
                <div className="min-w-0">
                  <p className="text-fg">{SLA_LABEL[c.sla]}</p>
                  <p className="text-[12px] text-subtle">
                    {c.partner} · due <span title={formatDateTime(c.due_at)}>{formatDateTime(c.due_at)}</span>
                    {c.met_at && <> · met {formatDateTime(c.met_at)}</>}
                  </p>
                </div>
                <Badge tone={SLA_STATUS[c.status].tone}>{SLA_STATUS[c.status].label}</Badge>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="px-5 py-4">
        <H>Sales activity</H>
        {s.activities.length === 0 ? <p className="text-[13px] text-muted">The partner has reported no calls, messages or stage changes yet.</p> : (
          <ol className="space-y-2.5">
            {s.activities.map((a) => (
              <li key={a.id} className="flex gap-3 text-[13px]">
                {(() => {
                  const Icon = a.kind === "call" && a.direction === "inbound" ? PhoneIncoming : KIND_ICON[a.kind as keyof typeof KIND_ICON] ?? StickyNote;
                  return <Icon className="mt-0.5 size-4 shrink-0 text-subtle" aria-hidden />;
                })()}
                <div className="min-w-0">
                  <p className="text-fg">
                    {ACTIVITY_LABEL[a.kind] ?? humanize(a.kind)}{a.direction === "inbound" && <span className="text-muted"> (inbound)</span>}
                    {a.outcome && <span className="text-muted"> · {humanize(a.outcome)}</span>}
                    {duration(a.duration_sec) && <span className="text-muted"> · {duration(a.duration_sec)}</span>}
                  </p>
                  <p className="text-[12px] text-subtle">
                    <time dateTime={a.occurred_at} title={formatDateTime(a.occurred_at)}>{relativeTime(a.occurred_at)}</time>
                    {" · "}{a.counsellor ? `${a.counsellor}, ${a.partner}` : a.partner}
                  </p>
                </div>
              </li>
            ))}
          </ol>
        )}
      </section>

      <section className="px-5 py-4">
        <H>Partner events</H>
        {s.events.length === 0 ? <p className="text-[13px] text-muted">No events received for this lead.</p> : (
          <ul className="space-y-2">
            {s.events.map((e) => (
              <li key={e.id}>
                <details className="group rounded-md border border-border">
                  <summary className="flex cursor-pointer list-none items-start justify-between gap-2 px-3 py-2 text-[13px]">
                    <div className="min-w-0">
                      <p className="text-fg">{e.event_type} <span className="font-mono text-[11px] text-subtle">{e.event_id}</span></p>
                      <p className="break-words text-[12px] text-muted">{e.result ?? "–"}</p>
                      <p className="text-[11.5px] text-subtle">{e.partner} · {relativeTime(e.received_at)}{e.mapping_version ? ` · mapping v${e.mapping_version}` : ""}</p>
                    </div>
                    <Badge tone={e.discarded ? "neutral" : EVENT_TONE[e.status] ?? "neutral"}>{e.discarded ? "Discarded" : EVENT_STATUS[e.status] ?? e.status}</Badge>
                  </summary>
                  <div className="space-y-2 border-t border-border px-3 py-2">
                    {e.discard_reason && <p className="text-[12px] text-muted">Discarded: {e.discard_reason}</p>}
                    <p className="text-[11px] font-medium uppercase tracking-wider text-subtle">Raw</p>
                    <pre className="max-h-48 overflow-auto rounded bg-surface-2 p-2 font-mono text-[11px] leading-4 text-fg">{JSON.stringify(e.raw, null, 2)}</pre>
                    {e.mapped !== null && e.mapped !== undefined && (
                      <>
                        <p className="text-[11px] font-medium uppercase tracking-wider text-subtle">Mapped</p>
                        <pre className="max-h-48 overflow-auto rounded bg-surface-2 p-2 font-mono text-[11px] leading-4 text-fg">{JSON.stringify(e.mapped, null, 2)}</pre>
                      </>
                    )}
                  </div>
                </details>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
