import Link from "next/link";
import type { Metadata } from "next";
import { Guide } from "@/components/guide/Guide";
import { PushToggle } from "@/components/shell/PushToggle";
import { Page, SetupError } from "@/components/shell/Page";
import { rpc } from "@/lib/data";
import type { Article } from "@/app/guide-actions";
import { requireUser } from "@/lib/auth";
import { date, inr, when } from "@/lib/format";
import { ROLE_LABEL } from "@/lib/labels";
import { createClient } from "@/lib/supabase/server";
import type { Enrollment } from "@/lib/types";
import { Availability } from "./Availability";
import { CalendarToggle, type CalendarMine } from "@/components/connectors/CalendarToggle";
import { googleSa } from "@/lib/gmail";
import { EmailTemplates, type EmailTemplate } from "./EmailTemplates";

export const metadata: Metadata = { title: "Me" };

const TABS = [["enrolments", "My enrolments"], ["templates", "Email templates"], ["availability", "Availability and alerts"], ["guide", "Guide"]] as const;

/** Me (spec B8.7): my enrolments, shared sales email templates, availability, and the guide. */
export default async function MePage({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const me = await requireUser("sales", "/s/me");
  const asked = (await searchParams).tab;
  const tab = TABS.some(([k]) => k === asked) ? asked! : "enrolments";
  const supabase = await createClient();
  let body: React.ReactNode;

  if (tab === "enrolments") {
    const { data } = await supabase.from("enrollments").select("id, lead_id, university, programme, fee, fee_paid, enrolled_on, status, note, counsellor_id, created_at")
      .eq("counsellor_id", me.user_id!).order("enrolled_on", { ascending: false }).limit(200);
    const rows = (data ?? []) as Enrollment[];
    const verified = rows.filter((r) => r.status === "verified");
    body = (
      <>
        <div className="grid g3">
          <div className="stat"><span className="small muted">Enrolments this month</span><b>{rows.filter((r) => r.enrolled_on >= new Date().toISOString().slice(0, 8) + "01").length}</b></div>
          <div className="stat"><span className="small muted">Verified by the Admin</span><b>{verified.length}</b></div>
          <div className="stat"><span className="small muted">Fees collected (verified)</span><b>{inr(verified.reduce((a, r) => a + Number(r.fee_paid ?? 0), 0))}</b></div>
        </div>
        <p className="note">Commission is worked out from verified enrolments. Eduwit moves no money from here.</p>
        <div className="list">
          {rows.length === 0 && <p className="empty">No enrolments yet.</p>}
          {rows.map((r) => (
            <Link key={r.id} className="li" href={`/s/leads/${r.lead_id}`}>
              <span className="avatar">{r.status === "verified" ? "✓" : "…"}</span>
              <span className="t ellipsis">{r.university} · {r.programme}</span>
              <span className={`chip ${r.status === "verified" ? "ok" : "risk"}`}>{r.status === "verified" ? "Verified" : r.status === "reported" ? "Waiting" : r.status}</span>
              <span className="s">{date(r.enrolled_on)} · fee {inr(r.fee)}{r.note ? ` · ${r.note}` : ""}</span>
            </Link>
          ))}
        </div>
      </>
    );
  } else if (tab === "templates") {
    const { data } = await supabase.from("sales_email_templates").select("id, owner_id, name, category, subject, body, parent_id, version, recommended, hidden, uses, updated_at")
      .is("deleted_at", null).order("recommended", { ascending: false }).order("uses", { ascending: false });
    body = <EmailTemplates templates={(data ?? []) as EmailTemplate[]} me={me.user_id!} />;
  } else if (tab === "availability") {
    const { data } = await supabase.from("users").select("away_until").eq("user_id", me.user_id!).maybeSingle();
    const away = data?.away_until && new Date(data.away_until) > new Date() ? data.away_until : null;
    body = (
      <div className="stack">
        <Availability awayUntil={away} label={away ? `Away until ${when(away)}` : "Working"} />
        <PushToggle vapidKey={process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY ?? null} />
        <section className="panel"><header><h3>Google Calendar</h3></header>
          <div className="body"><CalendarToggle mine={await rpc<CalendarMine>("calendar_mine").catch(() => null)} ready={!!googleSa()} /></div></section>
      </div>
    );
  } else {
    try {
      body = <Guide articles={await rpc<Article[]>("guides", { p_role: "sales", p_archived: false })} />;
    } catch (e) {
      body = <SetupError error={e} />;
    }
  }

  return (
    <Page title="Me" sub={`${me.email} · ${ROLE_LABEL[me.role ?? ""] ?? ""}`}>
      <div className="tabs" role="tablist">
        {TABS.map(([k, n]) => (
          <Link key={k} href={`/s/me?tab=${k}`} role="tab" aria-selected={tab === k}
            style={{ padding: "9px 12px", fontWeight: 600, textDecoration: "none", color: tab === k ? "var(--ink)" : "var(--muted)", borderBottom: `2px solid ${tab === k ? "var(--amber)" : "transparent"}` }}>
            {n}
          </Link>
        ))}
      </div>
      {body}
    </Page>
  );
}
