import { BellOff, Bot, FlaskConical, MessageCircle, SearchX, Trash2 } from "lucide-react";
import { Badge, EmptyState } from "@/components/ui/Card";
import { formatDateTime, relativeTime } from "@/lib/format";
import { DESTINATION_LABEL, formatPhone, humanize, statusTone, whatsappLink } from "@/lib/leads";
import type { LeadDetail } from "@/lib/leads-data";
import type { LeadRouting } from "@/lib/routing-data";
import { DrawerShell } from "./DrawerShell";
import { LeadActions } from "./LeadMutations";
import { RoutingTab } from "./RoutingTab";

type Lead = LeadDetail["lead"];
const str = (l: Lead, k: string): string | null => {
  const v = l[k];
  if (v === null || v === undefined || v === "") return null;
  return typeof v === "object" ? JSON.stringify(v) : String(v);
};
const when = (v: string | null) => (v ? formatDateTime(v) : null);
const yes = (v: string | null) => (v === null ? null : v === "true" ? "Yes" : "No");
const inr = (v: string | null) => (v === null ? null : `₹${Number(v).toLocaleString("en-IN")}`);

function Section({ title, rows }: { title: string; rows: [string, React.ReactNode | null][] }) {
  const shown = rows.filter(([, v]) => v !== null && v !== "");
  if (shown.length === 0) return null;
  return (
    <section className="px-5 py-4">
      <h3 className="mb-2 text-[11px] font-medium uppercase tracking-wider text-subtle">{title}</h3>
      <dl className="grid grid-cols-[minmax(120px,38%)_1fr] gap-x-4 gap-y-1.5 text-[13px]">
        {shown.map(([k, v]) => (
          <div key={k} className="contents">
            <dt className="text-muted">{k}</dt>
            <dd className="min-w-0 break-words text-fg">{v}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

function Overview({ l }: { l: Lead }) {
  const s = (k: string) => str(l, k);
  const place = [s("city"), s("state"), s("country")].filter(Boolean).join(", ") || s("current_city_country");
  const routing = s("destination_type");
  return (
    <div className="divide-y divide-border">
      <Section title="Contact" rows={[
        ["Email", s("email_id")],
        ["Alternate phone", s("alternate_phone") && formatPhone(s("alternate_phone"))],
        ["Phone verified", when(s("phone_verified_at"))],
        ["Location", place],
        ["Language", s("preferred_language") && humanize(s("preferred_language"))],
        ["Enquiring for", s("enquirer_relation") && humanize(s("enquirer_relation"))],
        ["Guardian", [s("guardian_name"), s("guardian_phone") && formatPhone(s("guardian_phone"))].filter(Boolean).join(" · ") || null],
        ["Best time to call", s("preferred_counseling_time")],
      ]} />
      <Section title="Interest" rows={[
        ["Course", s("interested_course")],
        ["Specialisation", s("interested_specialization")],
        ["Level", s("program_level") && humanize(s("program_level"))],
        ["Study mode", s("study_mode_preference") && humanize(s("study_mode_preference"))],
        ["University", s("interested_university") ?? s("university_preference")],
        ["Qualification", s("highest_qualification")],
        ["Currently studying", s("current_study")],
        ["Score", s("academic_score_pct") ? `${s("academic_score_pct")}%` : s("academic_percentage_gpa")],
        ["Work experience", s("work_experience_years_num") ? `${s("work_experience_years_num")} years` : s("work_experience_years")],
        ["Budget", inr(s("annual_budget_inr")) ?? s("annual_budget")],
        ["Timeline", s("enrollment_timeline")],
        ["Motivation", s("primary_motivation")],
      ]} />
      <Section title="Source" rows={[
        ["Source", s("lead_source") && humanize(s("lead_source"))],
        ["Channel", s("channel") && humanize(s("channel"))],
        ["Campaign", s("campaign")],
        ["UTM", [s("utm_source"), s("utm_medium"), s("utm_campaign")].filter(Boolean).join(" / ") || null],
        ["Referral code", s("referral_code") ?? s("referred_by_code")],
        ["Landing page", s("landing_url")],
        ["First touch", when(s("first_touch_at"))],
        ["Last touch", s("last_touch_at") && `${formatDateTime(s("last_touch_at"))}${s("last_touch_source") ? ` · ${humanize(s("last_touch_source"))}` : ""}`],
      ]} />
      <Section title="Routing and consent" rows={[
        ["Routing", routing ? (DESTINATION_LABEL[routing] ?? humanize(routing)) + (s("partner_id") ? ` #${s("partner_id")}` : "") : "Not routed"],
        ["Allocated", when(s("allocated_at"))],
        ["Partner stage", s("partner_stage_raw")],
        ["Partner sharing consent", s("consent_partner_share_at") ? formatDateTime(s("consent_partner_share_at")) : "Not given"],
        ["Sales contact consent", when(s("consent_sales_at"))],
        ["Opted out", s("opted_out_at") ? formatDateTime(s("opted_out_at")) : yes(s("is_opted_out"))],
        ["Enrollment", s("enrollment_status") && humanize(s("enrollment_status"))],
      ]} />
      <Section title="Witty" rows={[
        ["Conversation stage", s("lead_stage") && humanize(s("lead_stage"))],
        ["Intent", s("intent_type") && humanize(s("intent_type"))],
        ["Eligibility", s("eligibility_status") && humanize(s("eligibility_status"))],
        ["Bot paused", yes(s("is_bot_paused"))],
        ["Score", s("lead_score")],
      ]} />
      <Section title="Record" rows={[
        ["Lead ID", <span key="id" className="tabular">{l.id}</span>],
        ["Created", when(s("created_at"))],
        ["Updated", s("updated_at") && `${formatDateTime(s("updated_at"))}${s("updated_by") ? ` by ${s("updated_by")}` : ""}`],
        ["Deleted", when(s("deleted_at"))],
      ]} />
    </div>
  );
}

function Chat({ messages }: { messages: LeadDetail["messages"] }) {
  if (messages.length === 0) {
    return <EmptyState icon={MessageCircle} title="No Witty conversation">This lead has not chatted with Witty from this number.</EmptyState>;
  }
  return (
    <div className="space-y-2.5 bg-surface-2/50 px-4 py-4">
      <p className="text-center text-[11.5px] text-subtle">Read-only copy of the WhatsApp conversation with Witty{messages.length === 200 ? " (latest 200 messages)" : ""}</p>
      {messages.map((m, i) => {
        const mine = m.direction === "out";
        return (
          <div key={i} className={mine ? "flex justify-end" : "flex justify-start"}>
            <div className={mine
              ? "max-w-[85%] rounded-2xl rounded-br-md bg-navy px-3.5 py-2 text-white dark:bg-[var(--brand-navy-600)]"
              : "max-w-[85%] rounded-2xl rounded-bl-md border border-border bg-surface px-3.5 py-2 text-fg"}>
              <p className="whitespace-pre-wrap break-words text-[13px] leading-5">{m.content ?? ""}</p>
              <p className={mine ? "mt-1 text-right text-[10.5px] text-white/60" : "mt-1 text-[10.5px] text-subtle"}>
                {mine && <Bot className="mr-1 inline size-3 align-[-2px]" aria-label="Witty" />}
                {formatDateTime(m.at)}
              </p>
            </div>
          </div>
        );
      })}
    </div>
  );
}

type Item = { at: string; title: string; detail?: string | null; tone: "neutral" | "danger" | "success" | "info" };
const EVENT_LABEL: Record<string, string> = { "lead.deleted": "Moved to the recycle bin", "lead.restored": "Restored from the recycle bin" };

function Activity({ d }: { d: LeadDetail }) {
  const items: Item[] = [
    ...d.touchpoints.map((t): Item => ({
      at: t.at,
      title: humanize(t.event ?? "touchpoint"),
      detail: [t.system && humanize(t.system), t.source && humanize(t.source), t.campaign].filter(Boolean).join(" · ") || null,
      tone: "info",
    })),
    ...d.events.map((e): Item => ({
      at: e.at,
      title: EVENT_LABEL[e.type] ?? humanize(e.type.replace(/\./g, " ")),
      detail: typeof e.payload?.reason === "string" ? `Reason: ${humanize(e.payload.reason)}` : `By ${humanize(e.actor)}`,
      tone: e.type === "lead.deleted" ? "danger" : e.type === "lead.restored" ? "success" : "neutral",
    })),
    { at: String(d.lead.created_at), title: "Lead created", detail: str(d.lead, "lead_source") && humanize(str(d.lead, "lead_source")), tone: "success" } satisfies Item,
  ].sort((a, b) => Date.parse(b.at) - Date.parse(a.at));

  const dot = { neutral: "bg-subtle", danger: "bg-danger", success: "bg-success", info: "bg-info" };
  return (
    <ol className="relative px-5 py-4">
      {items.map((it, i) => (
        <li key={i} className="relative flex gap-3 pb-4 last:pb-0">
          {i < items.length - 1 && <span className="absolute left-[3.5px] top-3 h-full w-px bg-border" aria-hidden />}
          <span className={`relative mt-1.5 size-2 shrink-0 rounded-full ${dot[it.tone]}`} aria-hidden />
          <div className="min-w-0">
            <p className="text-[13px] font-medium text-fg">{it.title}</p>
            <p className="text-[12px] text-subtle">
              <time dateTime={it.at} title={formatDateTime(it.at)}>{relativeTime(it.at)}</time>
              {it.detail && <> · {it.detail}</>}
            </p>
          </div>
        </li>
      ))}
    </ol>
  );
}

/** Lead drawer: who the student is, their Witty chat and what happened to the lead. Read-only except delete/restore. */
export function LeadDrawer({ id, detail, routing, closeHref }: { id: number; detail: LeadDetail | null; routing: LeadRouting | null; closeHref: string }) {
  if (!detail) {
    return (
      <DrawerShell closeHref={closeHref} label="Lead not found" header={<h2 className="pb-4 text-[15px] font-semibold text-fg">Lead #{id}</h2>} tabs={[
        { id: "none", label: "Overview", content: <EmptyState icon={SearchX} title="Lead not found">It may have been merged into another lead.</EmptyState> },
      ]} />
    );
  }
  const l = detail.lead;
  const name = str(l, "student_name") ?? "Unnamed";
  const phone = str(l, "whatsapp_number");
  const wa = whatsappLink(phone);
  const status = str(l, "lead_status");

  const header = (
    <div className="pr-10">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h2 className="truncate text-[17px] font-semibold tracking-tight text-fg">{name}</h2>
          <p className="mt-0.5 flex flex-wrap items-center gap-x-2 text-[13px] text-muted">
            {wa ? <a href={wa} target="_blank" rel="noopener noreferrer" className="tabular hover:text-fg hover:underline">{formatPhone(phone)}</a> : <span className="tabular">{formatPhone(phone)}</span>}
            <span className="text-subtle">·</span>
            <span>#{l.id}</span>
            <span className="text-subtle">·</span>
            <span title={formatDateTime(str(l, "created_at"))}>{relativeTime(str(l, "created_at"))}</span>
          </p>
        </div>
        <LeadActions id={l.id} deleted={Boolean(l.deleted_at)} withPartner={l.destination_type === "partner"} hasEnrollment={detail.has_enrollment} />
      </div>
      <div className="mt-2.5 flex flex-wrap gap-1.5">
        {status && <Badge tone={statusTone(status)}>{humanize(status)}</Badge>}
        {str(l, "stage") && <Badge>{humanize(str(l, "stage"))}</Badge>}
        {l.deleted_at && <Badge tone="danger"><Trash2 className="size-3" /> In recycle bin</Badge>}
        {l.is_test && <Badge tone="brand"><FlaskConical className="size-3" /> Test lead</Badge>}
        {str(l, "is_opted_out") === "true" && <Badge tone="danger"><BellOff className="size-3" /> Opted out</Badge>}
        {str(l, "is_bot_paused") === "true" && <Badge tone="warning"><Bot className="size-3" /> Witty paused</Badge>}
      </div>
    </div>
  );

  return (
    <DrawerShell
      closeHref={closeHref}
      label={`Lead ${name}`}
      header={header}
      tabs={[
        { id: "overview", label: "Overview", content: <Overview l={l} /> },
        { id: "chat", label: "Witty chat", count: detail.messages.length, content: <Chat messages={detail.messages} /> },
        { id: "routing", label: "Routing", count: routing?.decisions.length, content: <RoutingTab leadId={l.id} r={routing} /> },
        { id: "activity", label: "Activity", count: detail.touchpoints.length + detail.events.length + 1, content: <Activity d={detail} /> },
      ]}
    />
  );
}
