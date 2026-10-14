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
import { BUCKETS, FollowupCards, type Bucket } from "./FollowupCards";

export const metadata: Metadata = { title: "Follow-ups" };

const ICON = { call: Phone, whatsapp: MessageCircle, email: Mail } as const;

/** Follow-ups (spec B8.3): not worked, overdue, due today, upcoming. Reminders arrive 10 minutes before each one. */
export default async function FollowupsPage({ searchParams }: { searchParams: Promise<{ b?: string }> }) {
  const me = await requireUser("sales", "/s/followups");
  const sp = await searchParams;
  const bucket: Bucket = BUCKETS.some(([k]) => k === sp.b) ? (sp.b as Bucket) : "overdue";
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
    <Page title="Follow-ups" sub="Reminders come 10 minutes before each follow-up; a missed one is escalated after 2 hours.">
      <FollowupCards counts={counts} active={bucket} />
      {rows.length === 0 ? <Empty>Nothing here.</Empty> : (
        <div className="list">
          {rows.map(({ task, lead: l }) => {
            const Icon = task ? ICON[task.kind as keyof typeof ICON] ?? CalendarClock : Phone;
            return (
              <div key={task?.id ?? l.lead_id} className="li" style={{ gridTemplateColumns: "auto 1fr auto" }}>
                <span className="avatar">{task ? <Icon className="icon s" aria-hidden /> : initials(l.name)}</span>
                <Link href={`/s/leads/${l.lead_id}`} className="t ellipsis" style={{ color: "inherit" }}>
                  {l.name ?? `Lead #${l.lead_id}`} <TempChip t={l.temperature} />
                </Link>
                <span className="row" style={{ gap: 6 }}>
                  {task ? <TaskActions taskId={task.id} title={task.title} leadId={l.lead_id} /> : <CallButton leadId={l.lead_id} name={l.name ?? "the student"} small />}
                </span>
                <span className="s row wrap" style={{ gap: 6 }}>
                  {task ? <>{TASK_KIND_LABEL[task.kind] ?? task.kind} · {task.title} · <b style={{ color: bucket === "overdue" ? "var(--red)" : undefined }}>{when(task.due_at)}</b></> : <>New · {l.course ?? "Programme not given"} <SlaChip lead={l} /></>}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </Page>
  );
}
