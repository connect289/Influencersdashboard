import type { Metadata } from "next";
import Link from "next/link";
import { CircleCheck, CircleDashed, Inbox, Mail, MessageCircle } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { CHANNEL_LABEL, KIND_LABEL, STATUS_LABEL, channelBlockers, type NotificationsOverview } from "@/lib/notifications";
import { notificationsOverview } from "@/lib/notifications-data";
import { ChannelSwitch } from "./ChannelSwitch";
import { SendLog } from "./SendLog";
import { SettingsForm } from "./SettingsForm";
import { TemplateEditor } from "./TemplateEditor";

export const metadata: Metadata = { title: "Notifications" };

const TABS = [
  { id: "overview", label: "Overview" },
  { id: "templates", label: "Templates" },
  { id: "providers", label: "Providers" },
] as const;
type Tab = (typeof TABS)[number]["id"];

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

function ChannelCard({ o, channel }: { o: NotificationsOverview; channel: "whatsapp" | "email" }) {
  const live = o.switches[channel];
  const blockers = channelBlockers(o, channel);
  const Icon = channel === "whatsapp" ? MessageCircle : Mail;
  const s = o.settings;
  const steps = channel === "whatsapp"
    ? [
        { done: Boolean(s.whatsapp.phone_number_id), label: "Phone number ID" },
        { done: s.whatsapp.has_token, label: "Access token stored" },
        { done: o.templates.some((t) => t.channel === "whatsapp" && t.status === "active" && t.wa_template), label: "Approved template active" },
      ]
    : [
        { done: Boolean(s.email.from_email), label: `Sender address${s.email.from_email ? ` ${s.email.from_email}` : ""}` },
        { done: s.email.has_key, label: `${s.email.provider === "brevo" ? "Brevo" : "Resend"} API key stored` },
        { done: o.templates.some((t) => t.channel === "email" && t.status === "active"), label: "Template active" },
      ];
  return (
    <Card className="min-w-0">
      <CardHeader
        title={CHANNEL_LABEL[channel]}
        description={channel === "whatsapp" ? "An approved template from Eduwit's WhatsApp Business number." : "A branded email with the partner's logo and an unsubscribe link."}
        action={<ChannelSwitch channel={channel} live={live} blockers={blockers} />}
      />
      <div className="space-y-3 px-5 py-4">
        <p className="flex items-center gap-2 text-[13px]">
          <Icon className="size-4 text-muted" />
          <Badge tone={live ? "success" : "neutral"}>{live ? "On" : "Off"}</Badge>
          <span className="text-muted">{live ? "Students are messaged when a partner accepts their lead." : "Nothing is sent on this channel."}</span>
        </p>
        <ul className="space-y-1.5">
          {steps.map((x) => (
            <li key={x.label} className="flex items-center gap-2 text-[13px]">
              {x.done ? <CircleCheck className="size-4 shrink-0 text-success" /> : <CircleDashed className="size-4 shrink-0 text-subtle" />}
              <span className={x.done ? "text-fg" : "text-muted"}>{x.label}</span>
            </li>
          ))}
        </ul>
        {!live && blockers.length > 0 && (
          <p className="text-[12.5px] text-muted">To turn it on: {blockers.join(" ")} <Link href={blockers[0]?.includes("template") ? "?tab=templates" : "?tab=providers"} className="text-info hover:underline">Fix it</Link></p>
        )}
      </div>
    </Card>
  );
}

function Overview({ o }: { o: NotificationsOverview }) {
  const counts = Object.entries(o.counts).sort((a, b) => b[1] - a[1]);
  const off = o.partners.filter((p) => !p.notify_enabled);
  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <ChannelCard o={o} channel="whatsapp" />
      <ChannelCard o={o} channel="email" />

      <Card className="min-w-0 xl:col-span-2">
        <CardHeader title="How it works" />
        <ul className="grid gap-x-8 gap-y-2 px-5 py-4 text-[13px] text-muted md:grid-cols-2">
          <li>One message per channel once a partner has accepted the lead (after its hold window), never before.</li>
          <li>Sent between {o.settings.quiet_start ?? "08:00"} and {o.settings.quiet_end ?? "21:00"} India time; later acceptances wait for the next morning.</li>
          <li>Hindi or Hinglish speakers get the Hindi template when it is active, others English.</li>
          <li>Never sent to test leads, students who opted out, bounced emails, or leads handed to B2C (the B2C CRM messages its own students).</li>
          <li>A failed message is retried once after a few minutes, then marked failed with an alert.</li>
          <li>{off.length === 0 ? "Every partner has notifications on." : `Notifications are off for ${off.map((p) => p.name).join(", ")} (partner settings).`}</li>
        </ul>
      </Card>

      <Card className="min-w-0 xl:col-span-2">
        <CardHeader title="Send log" description="The latest 100 messages. Phone numbers and emails are masked." />
        {counts.length > 0 && (
          <div className="flex flex-wrap gap-1.5 px-5 pt-4 text-[12px] text-muted">
            <span className="mr-1">Last 7 days:</span>
            {counts.map(([s, n]) => <Badge key={s}>{STATUS_LABEL[s] ?? s} <span className="tabular">{n}</span></Badge>)}
          </div>
        )}
        {o.log.length === 0
          ? <EmptyState icon={Inbox} title="No messages yet">They appear here once a partner accepts a lead, including the ones not sent and why.</EmptyState>
          : <div className="mt-3"><SendLog rows={o.log} /></div>}
      </Card>
    </div>
  );
}

export default async function NotificationsPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const tab: Tab = TABS.find((t) => t.id === sp.tab)?.id ?? "overview";
  const o = await notificationsOverview();
  const partners = o.partners.map((p) => ({ id: p.id, name: p.name }));
  const kinds = [...new Set(o.templates.map((t) => t.kind))];

  return (
    <>
      <PageHeader title="Notifications" description="What students hear from Eduwit once a partner accepts their lead: who will call and when." />
      <nav className="mb-6 flex gap-5 overflow-x-auto border-b border-border" aria-label="Notifications sections">
        {TABS.map((t) => (
          <Link key={t.id} href={`/notifications?tab=${t.id}`} aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px shrink-0 border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}>
            {t.label}
          </Link>
        ))}
      </nav>

      {tab === "overview" && <Overview o={o} />}
      {tab === "templates" && (
        <div className="space-y-6">
          {kinds.map((k) => (
            <Card key={k} className="min-w-0 overflow-hidden">
              <CardHeader title={KIND_LABEL[k] ?? k} description="Sent once the partner has accepted the lead. Only Active templates are sent." />
              <div className="divide-y divide-border">
                {o.templates.filter((t) => t.kind === k).map((t) => <TemplateEditor key={`${t.id}-${t.version}`} t={t} partners={partners} />)}
              </div>
            </Card>
          ))}
        </div>
      )}
      {tab === "providers" && (
        <Card className="min-w-0">
          <CardHeader title="Providers and quiet hours" description="WhatsApp goes through Meta's Cloud API, email through Resend or Brevo. Keys are stored encrypted in Supabase Vault." />
          <SettingsForm s={o.settings} version={o.version} />
        </Card>
      )}
    </>
  );
}
