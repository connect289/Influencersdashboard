import type { Metadata } from "next";
import Link from "next/link";
import { Activity, ArrowRight, BookOpen, Building2, Check, CircleDot, Radio, ShieldCheck, UserCheck } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { liveSwitches, recentEvents } from "@/lib/data";
import { formatDateTime } from "@/lib/format";

export const metadata: Metadata = { title: "Command Center" };

const KPIS = [
  { label: "Leads today", hint: "From every source" },
  { label: "Routed", hint: "Allocated to a partner" },
  { label: "Accepted", hint: "Hold window passed" },
  { label: "Duplicate rate", hint: "Last 7 days" },
  { label: "SLA compliance", hint: "First contact on time" },
  { label: "Commission (month)", hint: "Expected, net of GST" },
];

const SWITCH_LABELS: Record<string, string> = {
  whatsapp: "Student WhatsApp",
  email: "Student email",
  capi_meta: "Meta conversions",
  capi_google: "Google conversions",
};

export default async function CommandCenter() {
  const [switches, events] = await Promise.all([liveSwitches(), recentEvents()]);

  const steps = [
    { done: true, icon: ShieldCheck, title: "Admin access secured", text: "Allowlist, two-step verification and sign-in logging are on." },
    { done: false, icon: Building2, title: "Add the first partner", text: "Partner record, CRM connection, SLAs and working hours.", href: "/partners" },
    { done: false, icon: BookOpen, title: "Publish its programme file", text: "Excel or Google Sheet, matched to the catalogue.", href: "/programmes" },
    { done: false, icon: UserCheck, title: "Capture partner-sharing consent", text: "Witty and the forms must record it, or every lead falls back to B2C." },
    { done: false, icon: Radio, title: "Run 10 test leads, then go live", text: "Against the mock partner first; live switches stay off until you turn them on." },
  ];

  return (
    <>
      <PageHeader
        title="Command Center"
        description="Leads, routing, partner health and commission at a glance. Numbers appear here as soon as the first partner is live."
      />

      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        {KPIS.map((k) => (
          <Card key={k.label} className="p-4">
            <p className="text-[12px] font-medium text-muted">{k.label}</p>
            <p className="tabular mt-2 text-2xl font-semibold text-subtle" aria-label="No data yet">—</p>
            <p className="mt-1 text-[11.5px] text-subtle">{k.hint}</p>
          </Card>
        ))}
      </div>

      <div className="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
        <Card>
          <CardHeader title="Road to the first routed lead" description="What has to be in place before the engine allocates a real lead." />
          <ol className="divide-y divide-border">
            {steps.map((s, i) => {
              const body = (
                <div className="flex items-start gap-3.5 px-5 py-3.5">
                  <span className={cn("mt-0.5 grid size-6 shrink-0 place-items-center rounded-full border text-[11px] font-semibold",
                    s.done ? "border-success/30 bg-success-bg text-success" : "border-border bg-surface-2 text-subtle")}>
                    {s.done ? <Check className="size-3.5" /> : i + 1}
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className={cn("text-[13.5px] font-medium", s.done ? "text-muted line-through decoration-subtle/50" : "text-fg")}>{s.title}</p>
                    <p className="mt-0.5 text-[12.5px] text-muted">{s.text}</p>
                  </div>
                  {s.href && !s.done && <ArrowRight className="mt-1 size-4 text-subtle transition-transform group-hover:translate-x-0.5" />}
                </div>
              );
              return (
                <li key={s.title}>
                  {s.href && !s.done ? <Link href={s.href} className="group block hover:bg-surface-hover">{body}</Link> : body}
                </li>
              );
            })}
          </ol>
        </Card>

        <div className="space-y-6">
          <Card>
            <CardHeader title="Live switches" description="Nothing reaches a real partner, student or ad platform while these are off." />
            <ul className="divide-y divide-border">
              {switches.map((s) => (
                <li key={s.scope} className="flex items-center justify-between px-5 py-3">
                  <span className="text-[13px] text-fg">{SWITCH_LABELS[s.scope] ?? s.scope}</span>
                  {s.live ? <Badge tone="success"><CircleDot className="size-3" /> Live</Badge> : <Badge>Off</Badge>}
                </li>
              ))}
            </ul>
          </Card>

          <Card>
            <CardHeader title="Recent activity" description="From the B2B event log." />
            {events.length === 0 ? (
              <EmptyState icon={Activity} title="Quiet so far">Settings changes, routing decisions and partner events will stream here.</EmptyState>
            ) : (
              <ul className="divide-y divide-border">
                {events.map((e) => (
                  <li key={e.id} className="flex items-center justify-between gap-3 px-5 py-3">
                    <span className="truncate font-mono text-[12.5px] text-fg">{e.type}</span>
                    <span className="shrink-0 text-[12px] text-subtle">{formatDateTime(e.occurred_at)}</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>
      </div>
    </>
  );
}
