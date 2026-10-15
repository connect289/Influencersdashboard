import Link from "next/link";
import type { Metadata } from "next";
import { CalendarClock, Mail, MessageCircle, Phone } from "lucide-react";
import { CallButton } from "@/components/lead/CallButton";
import { SlaChip, TempChip, UntouchedChip } from "@/components/lead/Chips";
import { TaskActions } from "@/components/lead/TaskActions";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { initials, when } from "@/lib/format";
import { TASK_KIND_LABEL } from "@/lib/labels";
import { salesPeople, type Person } from "@/lib/people";
import type { LeadRow, Task } from "@/lib/types";
import { groupByDay, nextIndex } from "@/lib/workspace";
import { Calendar, type Item } from "./Calendar";
import { BUCKETS, FollowupCards, type Bucket } from "./FollowupCards";
import { Swipeable } from "@/components/ui/Swipeable";
import { Hotkeys } from "@/components/shell/Hotkeys";

export const metadata: Metadata = { title: "Follow-ups" };

const ICON = { call: Phone, whatsapp: MessageCircle, email: Mail } as const;

type Row = { task?: Task; lead: LeadRow };

/**
 * Follow-ups (spec B8.2): not worked, overdue, due today (the next one highlighted), upcoming by day. The Admin and the sales
 * head see everyone's, or one counsellor's. Reminders arrive 10 minutes before each one.
 */
export default async function FollowupsPage({ searchParams }: { searchParams: Promise<{ b?: string; view?: string; who?: string }> }) {
  const me = await requireUser("sales", "/s/followups");
  const sp = await searchParams;
  const lead = me.role === "admin" || me.role === "sales_head";
  // who: "me", "all" (the Admin and the sales head; their default) or a counsellor's id
  const who = !lead ? "me" : sp.who === "me" || (sp.who && /^[0-9a-f-]{36}$/i.test(sp.who)) ? sp.who : "all";
  const user = who === "all" ? null : who === "me" ? me.user_id : who;
  const query = lead ? `&who=${who}` : "";
  const bucket: Bucket = BUCKETS.some(([k]) => k === sp.b) ? (sp.b as Bucket) : "overdue";
  const view = sp.view === "day" || sp.view === "week" ? sp.view : "list";
  const people: Person[] = lead ? await salesPeople(me).catch(() => []) : [];
  const switcher = (
    <div className="pills" role="group" aria-label="Show as">
      {([["list", "List"], ["day", "Day"], ["week", "Week"]] as const).map(([k, l]) => (
        <Link key={k} className="pill" href={k === "list" ? `/s/followups?b=${bucket}${query}` : `/s/followups?view=${k}${query}`} aria-pressed={view === k} style={{ textDecoration: "none", color: "inherit" }}>{l}</Link>
      ))}
    </div>
  );
  const whoPicker = lead && (
    <form action="/s/followups" className="row wrap" style={{ gap: 6 }}>
      {view !== "list" ? <input type="hidden" name="view" value={view} /> : <input type="hidden" name="b" value={bucket} />}
      <select className="input" name="who" defaultValue={who} style={{ width: "auto" }} aria-label="Whose follow-ups">
        <option value="all">{me.role === "sales_head" ? "Everyone in my team" : "Everyone"}</option>
        <option value="me">Mine</option>
        {people.filter((p) => p.user_id !== me.user_id).map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
      </select>
      <button className="btn ghost sm" type="submit">Show</button>
    </form>
  );
  const showOwner = lead && who !== "me" && user !== me.user_id;

  if (view !== "list") {
    let items: Item[];
    try {
      const all = await Promise.all((["overdue", "today", "upcoming"] as const).map((b) => rpc<Item[]>("followups", { p_bucket: b, p_user: user })));
      const end = Date.now() + (view === "day" ? 1 : 7) * 86400000;
      items = all.flat().filter((i) => i.task && new Date(i.task.due_at).getTime() < end);
    } catch (e) {
      return <Page title="Follow-ups"><SetupError error={e} /></Page>;
    }
    return <Page title="Follow-ups" sub="Tap a follow-up to open the lead." actions={switcher}>{whoPicker}<Calendar items={items} view={view} /></Page>;
  }

  let counts: Record<Bucket, number>;
  let rows: Row[];
  try {
    if (user) {
      [counts, rows] = await Promise.all([rpc<Record<Bucket, number>>("followup_counts", { p_user: user }), rpc<Row[]>("followups", { p_bucket: bucket, p_user: user })]);
    } else {
      // everyone: b2c.followup_counts counts one person, so count the four lists
      const lists = await Promise.all(BUCKETS.map(([k]) => rpc<Row[]>("followups", { p_bucket: k, p_user: null })));
      counts = Object.fromEntries(BUCKETS.map(([k], i) => [k, lists[i]!.length])) as Record<Bucket, number>;
      rows = lists[BUCKETS.findIndex(([k]) => k === bucket)]!;
    }
  } catch (e) {
    return <Page title="Follow-ups"><SetupError error={e} /></Page>;
  }
  const next = bucket === "today" ? nextIndex(rows, (r) => r.task?.due_at) : -1;
  const groups = bucket === "upcoming" ? groupByDay(rows, (r) => r.task?.due_at) : [{ day: "", label: "", rows }];

  const row = ({ task, lead: l }: Row, highlight: boolean) => {
    const Icon = task ? ICON[task.kind as keyof typeof ICON] ?? CalendarClock : Phone;
    return (
      <Swipeable key={task?.id ?? l.lead_id} right={{ label: "Call", selector: ".btn.call" }} left={task ? { label: "Snooze", selector: "button[data-move]", tone: "primary" } : { label: "WhatsApp", selector: "a[href^='/s/inbox']", tone: "primary" }}>
        <div className="li" style={{ gridTemplateColumns: "auto 1fr auto", ...(highlight ? { boxShadow: "inset 3px 0 0 var(--amber)", background: "var(--amber-soft)" } : {}) }} data-row aria-current={highlight ? "true" : undefined}>
          <span className="avatar">{task ? <Icon className="icon s" aria-hidden /> : initials(l.name)}</span>
          <Link href={`/s/leads/${l.lead_id}`} className="t ellipsis" style={{ color: "inherit" }}>
            {l.name ?? `Lead #${l.lead_id}`} <TempChip t={l.temperature} /> {highlight && <span className="chip hot">Next</span>}
          </Link>
          <span className="row" style={{ gap: 6 }}>
            <CallButton leadId={l.lead_id} name={l.name ?? "the student"} small label="" />
            <Link className="btn ghost sm" href={`/s/inbox?lead=${l.lead_id}`} aria-label={`WhatsApp ${l.name ?? "the student"}`}><MessageCircle className="icon s" aria-hidden /></Link>
            {task && <TaskActions taskId={task.id} title={task.title} leadId={l.lead_id} moveLabel="Snooze" />}
          </span>
          <span className="s row wrap" style={{ gap: 6 }}>
            <span className="muted">{l.course ?? "Programme not given"}{showOwner ? ` · ${l.owner_name ?? "Unassigned"}` : ""}</span>
            {task ? <>· {TASK_KIND_LABEL[task.kind] ?? task.kind}: {task.title}{task.note ? <span className="muted"> ({task.note})</span> : null} · <b style={{ color: bucket === "overdue" ? "var(--red)" : undefined }}>{when(task.due_at)}</b></>
              : <>· New <SlaChip lead={l} /></>}
            <UntouchedChip lead={l} />
          </span>
        </div>
      </Swipeable>
    );
  };

  return (
    <Page title="Follow-ups" sub="Reminders come 10 minutes before each follow-up; a missed one is escalated after 2 hours." actions={switcher}>
      {whoPicker}
      <FollowupCards counts={counts} active={bucket} query={query} />
      <Hotkeys keys={[]} />
      {rows.length === 0 ? <Empty>Nothing here.</Empty> : groups.map((g) => (
        <section key={g.day || "all"} className="stack tight">
          {g.label && <div className="sec-title"><h2>{g.label}</h2><span className="note">{g.rows.length}</span></div>}
          <div className="list">{g.rows.map((r) => row(r, bucket === "today" && rows.indexOf(r) === next))}</div>
        </section>
      ))}
    </Page>
  );
}
