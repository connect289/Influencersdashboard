import Link from "next/link";
import type { Metadata } from "next";
import { CalendarClock, Mail, MessageCircle, Phone } from "lucide-react";
import { CallButton } from "@/components/lead/CallButton";
import { SlaChip, TempChip } from "@/components/lead/Chips";
import { TaskActions } from "@/components/lead/TaskActions";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { initials, when } from "@/lib/format";
import { TASK_KIND_LABEL } from "@/lib/labels";
import type { LeadRow, Task } from "@/lib/types";
import { Calendar, type Item } from "./Calendar";
import { BUCKETS, FollowupCards, type Bucket } from "./FollowupCards";
import { Swipeable } from "@/components/ui/Swipeable";
import { Hotkeys } from "@/components/shell/Hotkeys";

export const metadata: Metadata = { title: "Follow-ups" };

const ICON = { call: Phone, whatsapp: MessageCircle, email: Mail } as const;

/** Follow-ups (spec B8.3): not worked, overdue, due today, upcoming. Reminders arrive 10 minutes before each one. */
export default async function FollowupsPage({ searchParams }: { searchParams: Promise<{ b?: string; view?: string }> }) {
  const me = await requireUser("sales", "/s/followups");
  const sp = await searchParams;
  const bucket: Bucket = BUCKETS.some(([k]) => k === sp.b) ? (sp.b as Bucket) : "overdue";
  const view = sp.view === "day" || sp.view === "week" ? sp.view : "list";
  const switcher = (
    <div className="pills" role="group" aria-label="Show as">
      {([["list", "List"], ["day", "Day"], ["week", "Week"]] as const).map(([k, l]) => (
        <Link key={k} className="pill" href={k === "list" ? `/s/followups?b=${bucket}` : `/s/followups?view=${k}`} aria-pressed={view === k} style={{ textDecoration: "none", color: "inherit" }}>{l}</Link>
      ))}
    </div>
  );
  if (view !== "list") {
    let items: Item[];
    try {
      const all = await Promise.all((["overdue", "today", "upcoming"] as const).map((b) => rpc<Item[]>("followups", { p_bucket: b, p_user: null })));
      const end = Date.now() + (view === "day" ? 1 : 7) * 86400000;
      items = all.flat().filter((i) => i.task && new Date(i.task.due_at).getTime() < end);
    } catch (e) {
      return <Page title="Follow-ups"><SetupError error={e} /></Page>;
    }
    return <Page title="Follow-ups" sub="Tap a follow-up to open the lead." actions={switcher}><Calendar items={items} view={view} /></Page>;
  }
  let counts: Record<Bucket, number>;
  let rows: { task?: Task; lead: LeadRow }[];
  try {
    [counts, rows] = await Promise.all([
      rpc<Record<Bucket, number>>("followup_counts", { p_user: me.user_id }),
      rpc<{ task?: Task; lead: LeadRow }[]>("followups", { p_bucket: bucket, p_user: null }),
    ]);
  } catch (e) {
    return <Page title="Follow-ups"><SetupError error={e} /></Page>;
  }
  return (
    <Page title="Follow-ups" sub="Reminders come 10 minutes before each follow-up; a missed one is escalated after 2 hours." actions={switcher}>
      <FollowupCards counts={counts} active={bucket} />
      <Hotkeys keys={[]} />
      {rows.length === 0 ? <Empty>Nothing here.</Empty> : (
        <div className="list">
          {rows.map(({ task, lead: l }) => {
            const Icon = task ? ICON[task.kind as keyof typeof ICON] ?? CalendarClock : Phone;
            return (
              <Swipeable key={task?.id ?? l.lead_id} right={{ label: "Call", selector: ".btn.call" }} left={task ? { label: "Snooze", selector: "button[data-move]", tone: "primary" } : { label: "WhatsApp", selector: "a[href^='/s/inbox']", tone: "primary" }}>
              <div className="li" style={{ gridTemplateColumns: "auto 1fr auto" }} data-row>
                <span className="avatar">{task ? <Icon className="icon s" aria-hidden /> : initials(l.name)}</span>
                <Link href={`/s/leads/${l.lead_id}`} className="t ellipsis" style={{ color: "inherit" }}>
                  {l.name ?? `Lead #${l.lead_id}`} <TempChip t={l.temperature} />
                </Link>
                <span className="row" style={{ gap: 6 }}>
                  <CallButton leadId={l.lead_id} name={l.name ?? "the student"} small label="" />
                  <Link className="btn ghost sm" href={`/s/inbox?lead=${l.lead_id}`} aria-label={`WhatsApp ${l.name ?? "the student"}`}><MessageCircle className="icon s" aria-hidden /></Link>
                  {task && <TaskActions taskId={task.id} title={task.title} leadId={l.lead_id} moveLabel="Snooze" />}
                </span>
                <span className="s row wrap" style={{ gap: 6 }}>
                  {task ? <>{TASK_KIND_LABEL[task.kind] ?? task.kind} · {task.title} · <b style={{ color: bucket === "overdue" ? "var(--red)" : undefined }}>{when(task.due_at)}</b></> : <>New · {l.course ?? "Programme not given"} <SlaChip lead={l} /></>}
                </span>
              </div>
              </Swipeable>
            );
          })}
        </div>
      )}
    </Page>
  );
}
