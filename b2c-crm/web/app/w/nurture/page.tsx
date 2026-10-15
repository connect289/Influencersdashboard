import Link from "next/link";
import type { Metadata } from "next";
import { CampaignCalendar } from "./CampaignCalendar";
import { Page, SetupError, Empty } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { inr, when } from "@/lib/format";
import { stagesAndSubs } from "@/lib/stages";
import { createClient } from "@/lib/supabase/server";
import {
  CampaignActions, CampaignButton, NewJourneyButton, OverlapTool, ReplyRow, ScoreRuleRow, SegmentButton, SuppressForm,
  type Campaign, type Reply, type ScoreRule, type Segment, type Template,
} from "./parts";

export const metadata: Metadata = { title: "Nurture" };

const TABS = [["overview", "Overview"], ["pool", "Pool"], ["journeys", "Journeys"], ["campaigns", "Campaigns"], ["segments", "Segments"], ["replies", "Replies"], ["scoring", "Scoring and rules"]] as const;
type Tab = (typeof TABS)[number][0];

type Overview = {
  pool: number; dormant: number; by_reason: { reason: string; age: string; n: number }[]; flow_14d: { day: string; in: number; reengaged: number }[];
  reengaged_30d: number; entered_30d: number; hours_to_reengage: number | null; messages_today: { whatsapp: number; email: number };
  email_allowance: { limit: number; left: number }; wa_cost_30d: number; replies_today: Record<string, number>; replies_waiting: number;
  suppressed_today: Record<string, number>; wa_quality: { rating?: string; tier?: string; at?: string } | null; journeys_running: number;
};
type PoolRow = {
  lead_id: number; name: string | null; course: string | null; reason: string | null; sub_stage: string | null; lost_by: string | null; lost_detail: string | null;
  lost_reason: string | null; missing: string[]; score: number | null; trend_7d: number; marketing_consent: { whatsapp: boolean; email: boolean };
  journey: { name: string; step: number; status: string; next_at: string } | null; first_message_due_at: string | null; pool_entered_at: string | null;
  last_message: { status: string; at: string } | null; last_student_at: string | null;
};
type Journey = { id: number; key: string; name: string; description: string | null; trigger: { type: string; reasons?: string[]; sub_stages?: string[] }; status: string; current_version: number; test_mode: boolean; priority: number };

/** The Nurture page (spec B9.0): every nurture programme for every type of lead. Admin and Marketing. */
export default async function NurturePage({ searchParams }: { searchParams: Promise<{ tab?: string; reason?: string; q?: string; test?: string; status?: string; m?: string }> }) {
  const me = await requireUser("workspace", "/w/nurture");
  if (me.role !== "admin" && me.role !== "marketing") return <Page title="Nurture"><Empty>The Nurture page is for Marketing and the Admin.</Empty></Page>;
  const sp = await searchParams;
  const tab: Tab = TABS.some(([k]) => k === sp.tab) ? (sp.tab as Tab) : "overview";
  const admin = me.role === "admin";
  const supabase = await createClient();
  let body: React.ReactNode;

  try {
    if (tab === "overview") {
      const o = await rpc<Overview>("nurture_overview");
      const flowMax = Math.max(1, ...o.flow_14d.map((d) => Math.max(d.in, d.reengaged)));
      const supp = Object.entries(o.suppressed_today);
      body = (
        <div className="stack">
          <div className="grid g4">
            <div className="stat"><span className="small muted">In the pool</span><b>{o.pool}</b><span className="delta">{o.dormant} dormant</span></div>
            <div className="stat"><span className="small muted">Re-engaged, 30 days</span><b>{o.reengaged_30d}</b><span className="delta">{o.entered_30d ? Math.round((o.reengaged_30d / o.entered_30d) * 100) : 0}% of {o.entered_30d} entered{o.hours_to_reengage !== null ? ` · median ${o.hours_to_reengage} h` : ""}</span></div>
            <div className="stat"><span className="small muted">Messages today</span><b>{o.messages_today.whatsapp + o.messages_today.email}</b><span className="delta">{o.messages_today.whatsapp} WhatsApp · {o.messages_today.email} email ({o.email_allowance.left} of {o.email_allowance.limit} left)</span></div>
            <div className="stat"><span className="small muted">WhatsApp spend, 30 days</span><b>{inr(o.wa_cost_30d)}</b><span className="delta">{o.reengaged_30d ? `${inr(o.wa_cost_30d / o.reengaged_30d)} per re-engaged lead` : "estimate from the rate card"}</span></div>
          </div>
          {o.wa_quality?.rating && o.wa_quality.rating !== "GREEN" && <div className="banner danger">WhatsApp quality rating is <b>{o.wa_quality.rating}</b>. Slow down marketing on the B2C number.</div>}
          {o.replies_waiting > 0 && <div className="banner info"><div className="grow"><b>{o.replies_waiting} replies</b> wait for a person.</div><Link className="btn ghost sm" href="/w/nurture?tab=replies">Open replies</Link></div>}
          <div className="grid g2">
            <section className="card pad stack">
              <h2>Pool by reason and age</h2>
              {o.by_reason.length === 0 ? <p className="note">The pool is empty.</p> : (
                <div className="table-wrap"><table>
                  <thead><tr><th>Reason</th><th>Age</th><th className="right">Leads</th></tr></thead>
                  <tbody>{o.by_reason.map((r) => <tr key={r.reason + r.age}><td>{r.reason}</td><td>{r.age}</td><td className="right num">{r.n}</td></tr>)}</tbody>
                </table></div>
              )}
            </section>
            <section className="card pad stack">
              <h2>In and out, 14 days</h2>
              {o.flow_14d.map((d) => (
                <div key={d.day} className="funnel-row small">
                  <span className="mono">{d.day.slice(5)}</span>
                  <div className="stack" style={{ gap: 2 }}>
                    <div className="bar-track"><div className="bar-fill amber" style={{ width: `${(d.in / flowMax) * 100}%` }} /></div>
                    <div className="bar-track"><div className="bar-fill" style={{ width: `${(d.reengaged / flowMax) * 100}%` }} /></div>
                  </div>
                  <span className="num right">{d.in}/{d.reengaged}</span>
                </div>
              ))}
              <div className="row small"><span className="chip warm">■ Entered</span><span className="chip soft">■ Re-engaged</span></div>
            </section>
          </div>
          <div className="grid g2">
            <section className="card pad stack">
              <h2>Guardrails today</h2>
              {supp.length === 0 ? <p className="note">Nothing held back today.</p> : <p>{supp.reduce((a, [, n]) => a + n, 0)} leads held back: {supp.map(([k, n]) => `${n} ${k.replace(/^wait: /, "")}`).join(", ")}.</p>}
              <p className="note">Quiet hours, at most 1 marketing WhatsApp a day and 6 in 30 days, 2 emails a day, nothing during a Witty chat or active sales, one journey at a time. Change them under Settings → messaging.</p>
            </section>
            <section className="card pad stack">
              <h2>Replies today</h2>
              {Object.keys(o.replies_today).length === 0 ? <p className="note">No replies yet today.</p> : (
                <div className="row wrap" style={{ gap: 6 }}>{Object.entries(o.replies_today).map(([k, n]) => <span key={k} className="chip soft">{k}: {n}</span>)}</div>
              )}
              <p className="small muted">{o.journeys_running} leads in a journey now.</p>
            </section>
          </div>
        </div>
      );
    } else if (tab === "pool") {
      const res = await rpc<{ total: number; rows: PoolRow[] }>("pool_list", { p: { reason: sp.reason || null, q: sp.q || null, test: sp.test === "1", limit: 200 } });
      body = (
        <div className="stack">
          <form className="row wrap" action="/w/nurture" style={{ gap: 6 }}>
            <input type="hidden" name="tab" value="pool" />
            <input className="input grow" name="q" defaultValue={sp.q ?? ""} placeholder="Name, phone or lead #" aria-label="Search the pool" />
            <select className="input" name="reason" defaultValue={sp.reason ?? ""} aria-label="Reason">
              <option value="">Every reason</option><option value="partner_lost">Partner lost</option><option value="counsellor_lost">Counsellor lost</option><option value="not_qualified">Not qualified</option>
            </select>
            <label className="checkbox"><input type="checkbox" name="test" value="1" defaultChecked={sp.test === "1"} /> Test leads</label>
            <button className="btn ghost sm" type="submit">Show</button>
          </form>
          <p className="small muted">{res.total} leads</p>
          <div className="table-wrap"><table>
            <thead><tr><th>Lead</th><th>Why in the pool</th><th>Missing</th><th className="right">Score</th><th>Consent</th><th>Journey</th><th>Last message</th><th>Last reply</th></tr></thead>
            <tbody>
              {res.rows.length === 0 && <tr><td colSpan={8} className="muted">Nobody here.</td></tr>}
              {res.rows.map((r) => (
                <tr key={r.lead_id}>
                  <td><Link href={`/w/leads/${r.lead_id}`}><b>{r.name ?? `#${r.lead_id}`}</b></Link><div className="small muted">{r.course ?? "—"}</div></td>
                  <td>{r.reason === "partner_lost" ? `Partner lost${r.lost_detail ? ` (${r.lost_detail})` : ""}` : r.reason === "counsellor_lost" ? `Lost by ${r.lost_detail ?? "a counsellor"}` : r.reason ?? "—"}<div className="small muted">{r.lost_reason ?? ""}</div></td>
                  <td className="small">{(r.missing ?? []).join(", ") || "—"}</td>
                  <td className="right num">{r.score ?? 0}<span className={`small ${r.trend_7d > 0 ? "" : "muted"}`}>{r.trend_7d ? ` ${r.trend_7d > 0 ? "+" : ""}${Math.round(r.trend_7d)}` : ""}</span></td>
                  <td className="small">{r.marketing_consent.whatsapp ? "WA" : "—"} · {r.marketing_consent.email ? "Email" : "—"}</td>
                  <td className="small">{r.journey ? `${r.journey.name} · step ${r.journey.step}${r.journey.status === "paused" ? " (paused)" : ""}` : r.first_message_due_at && new Date(r.first_message_due_at) > new Date() ? `Starts ${when(r.first_message_due_at)}` : "—"}</td>
                  <td className="small">{r.last_message ? `${r.last_message.status} · ${when(r.last_message.at)}` : "—"}</td>
                  <td className="small">{when(r.last_student_at)}</td>
                </tr>
              ))}
            </tbody>
          </table></div>
        </div>
      );
    } else if (tab === "journeys") {
      const { data } = await supabase.from("journeys").select("id, key, name, description, trigger, status, current_version, test_mode, priority").neq("status", "archived").order("priority").order("name");
      const journeys = (data ?? []) as Journey[];
      const stats = await Promise.all(journeys.map((j) => rpc<{ entered: number; running: number; re_engaged: number; enrolled: number }>("journey_stats", { p_id: j.id })));
      body = (
        <div className="stack">
          <div className="row between"><p className="note">Pooled leads enter the journey their lost reason names, after its delay. The starter journeys begin paused: review each one and set it running.</p><NewJourneyButton /></div>
          <div className="table-wrap"><table>
            <thead><tr><th>Journey</th><th>Starts for</th><th>Status</th><th className="right">In it now</th><th className="right">Entered</th><th className="right">Re-engaged</th><th className="right">Enrolled</th></tr></thead>
            <tbody>{journeys.map((j, i) => (
              <tr key={j.id}>
                <td><Link href={`/w/nurture/journeys/${j.id}`}><b>{j.name}</b></Link><div className="small muted">{j.description ?? ""}</div></td>
                <td className="small">{j.trigger.type === "pool_entry" ? (j.trigger.sub_stages?.join(", ") ?? j.trigger.reasons?.join(", ") ?? "Pool entry") : j.trigger.type}</td>
                <td><span className={`chip ${j.status === "active" ? "ok" : j.status === "paused" ? "risk" : "line"}`}>{j.status}</span>{j.test_mode && <span className="chip line"> test mode</span>}<div className="small muted">v{j.current_version}</div></td>
                <td className="right num">{stats[i]!.running}</td><td className="right num">{stats[i]!.entered}</td><td className="right num">{stats[i]!.re_engaged}</td><td className="right num">{stats[i]!.enrolled}</td>
              </tr>
            ))}</tbody>
          </table></div>
        </div>
      );
    } else if (tab === "campaigns" || tab === "segments") {
      const [{ data: segs }, { data: camps }, { data: wa }, { data: em }] = await Promise.all([
        supabase.from("segments").select("id, name, description, kind, filters").is("archived_at", null).order("name"),
        supabase.from("campaigns").select("*").order("created_at", { ascending: false }).limit(100),
        supabase.from("wa_templates").select("id, name, status").eq("audience", "marketing").is("archived_at", null).order("name"),
        supabase.from("email_templates").select("id, name").is("archived_at", null).order("name"),
      ]);
      const segments = (segs ?? []) as Segment[];
      const templates: Template[] = [...(wa ?? []).map((t) => ({ ...t, channel: "whatsapp" as const })), ...(em ?? []).map((t) => ({ ...t, channel: "email" as const }))];
      if (tab === "segments") {
        const { stages } = await stagesAndSubs();
        const counts = await Promise.all(segments.map((s) => rpc<Record<string, number>>("segment_count", { p_segment: s.id, p_filters: null })));
        body = (
          <div className="stack">
            <div className="row between wrap"><OverlapTool segments={segments} /><SegmentButton stages={stages} /></div>
            <div className="table-wrap"><table>
              <thead><tr><th>Segment</th><th>Kind</th><th className="right">Leads</th><th className="right">WhatsApp consent</th><th className="right">Email consent</th><th className="right">In active sales</th><th /></tr></thead>
              <tbody>
                {segments.length === 0 && <tr><td colSpan={7} className="muted">No segments yet.</td></tr>}
                {segments.map((s, i) => (
                  <tr key={s.id}>
                    <td><b>{s.name}</b><div className="small muted">{s.description ?? ""}</div></td><td>{s.kind}</td>
                    <td className="right num">{counts[i]!.leads}</td><td className="right num">{counts[i]!.whatsapp_consent}</td><td className="right num">{counts[i]!.email_consent}</td><td className="right num">{counts[i]!.in_active_sales}</td>
                    <td><SegmentButton stages={stages} segment={s} /></td>
                  </tr>
                ))}
              </tbody>
            </table></div>
          </div>
        );
      } else {
        const campaigns = (camps ?? []) as Campaign[];
        const segName = new Map(segments.map((s) => [s.id, s.name]));
        const tplName = new Map(templates.map((t) => [`${t.channel}:${t.id}`, t.name]));
        body = (
          <div className="stack">
            <CampaignCalendar month={sp.m} />
            <div className="row between"><p className="note">Campaigns send within their window and throttle; the guardrails decide for each lead. Test mode reaches test leads only.</p>
              {segments.length ? <CampaignButton segments={segments} templates={templates} admin={admin} /> : <Link className="btn ghost sm" href="/w/nurture?tab=segments">Make a segment first</Link>}</div>
            <div className="table-wrap"><table>
              <thead><tr><th>Campaign</th><th>Segment and template</th><th>When</th><th>Status</th><th /></tr></thead>
              <tbody>
                {campaigns.length === 0 && <tr><td colSpan={5} className="muted">No campaigns yet.</td></tr>}
                {campaigns.map((c) => (
                  <tr key={c.id}>
                    <td><b>{c.name}</b><div className="small muted">{c.channel === "whatsapp" ? "WhatsApp" : "Email"}{c.test_only ? " · test mode" : ""}{c.allow_active_sales ? " · reaches active sales" : ""}</div></td>
                    <td className="small">{segName.get(c.segment_id ?? 0) ?? "—"}<div className="muted">{tplName.get(`${c.channel}:${c.template_id}`) ?? "—"}{c.template_b_id ? ` vs ${tplName.get(`${c.channel}:${c.template_b_id}`) ?? "?"} (${c.ab_pct}%)${c.winner ? `, ${c.winner.toUpperCase()} won` : ""}` : ""}</div></td>
                    <td className="small">{c.schedule_at ? when(c.schedule_at) : "When scheduled"}{c.recurring ? ` · ${c.recurring}` : ""}{c.window_start ? ` · ${c.window_start.slice(0, 5)}–${(c.window_end ?? "20:00").slice(0, 5)}` : ""}</td>
                    <td><span className={`chip ${c.status === "running" ? "ok" : c.status === "paused" ? "risk" : "line"}`}>{c.status}</span></td>
                    <td className="row" style={{ gap: 4 }}>{(c.status === "draft" || c.status === "paused") && <CampaignButton segments={segments} templates={templates} admin={admin} campaign={c} />}<CampaignActions c={c} /></td>
                  </tr>
                ))}
              </tbody>
            </table></div>
          </div>
        );
      }
    } else if (tab === "replies") {
      const status = sp.status === "all" ? "all" : "inbox";
      const rows = await rpc<Reply[]>("replies_list", { p: { status, limit: 100 } });
      body = (
        <div className="stack">
          <div className="hscroll">
            <Link className="pill" href="/w/nurture?tab=replies" aria-pressed={status === "inbox"} style={{ color: "inherit", textDecoration: "none" }}>Waiting</Link>
            <Link className="pill" href="/w/nurture?tab=replies&status=all" aria-pressed={status === "all"} style={{ color: "inherit", textDecoration: "none" }}>All recent</Link>
          </div>
          {rows.length === 0 ? <Empty>No reply waits for a person.</Empty> : rows.map((r) => <ReplyRow key={r.reply.id} r={r} />)}
        </div>
      );
    } else {
      const [{ data: rules }, { data: replyRules }] = await Promise.all([
        supabase.from("score_rules").select("key, kind, label, points, active").order("kind").order("key"),
        supabase.from("reply_rules").select("class, pattern, confidence, lang, active").order("sort"),
      ]);
      body = (
        <div className="stack">
          <section className="stack">
            <h2>Lead scoring</h2>
            <p className="note">Score = fit + engagement. Engagement halves after 14 days without activity. A rise to 60 or more after a lead entered the pool, with engagement since, hands it to a counsellor; fit alone never does.</p>
            <div className="table-wrap"><table>
              <thead><tr><th>Rule</th><th>Kind</th><th>Points</th><th>On</th><th /></tr></thead>
              <tbody>{((rules ?? []) as ScoreRule[]).filter((r) => r.key !== "journey").map((r) => <ScoreRuleRow key={r.key} r={r} />)}</tbody>
            </table></div>
          </section>
          <section className="stack">
            <h2>Reply rules</h2>
            <p className="note">Keyword rules decide first (English, Hindi, Hinglish); what they cannot decide goes to Claude with only the reply text and the course interest; below 80% confidence a person decides.</p>
            <div className="table-wrap"><table>
              <thead><tr><th>Class</th><th>Pattern</th><th className="right">Confidence</th><th>Language</th></tr></thead>
              <tbody>{(replyRules ?? []).map((r, i) => <tr key={i}><td>{r.class}</td><td className="mono small">{r.pattern}</td><td className="right num">{Math.round(Number(r.confidence) * 100)}%</td><td>{r.lang}</td></tr>)}</tbody>
            </table></div>
          </section>
          <section className="stack">
            <h2>Suppression list</h2>
            <p className="note">A number or address here never gets marketing, whoever it belongs to.</p>
            <SuppressForm />
          </section>
        </div>
      );
    }
  } catch (e) {
    body = <SetupError error={e} />;
  }

  return (
    <Page title="Nurture" sub="The pool, journeys, campaigns, segments and replies">
      <div className="tabs" role="tablist">
        {TABS.map(([k, n]) => (
          <Link key={k} href={`/w/nurture?tab=${k}`} role="tab" aria-selected={tab === k}
            style={{ padding: "9px 12px", fontWeight: 600, textDecoration: "none", color: tab === k ? "var(--ink)" : "var(--muted)", borderBottom: `2px solid ${tab === k ? "var(--amber)" : "transparent"}`, whiteSpace: "nowrap" }}>
            {n}
          </Link>
        ))}
      </div>
      {body}
    </Page>
  );
}
