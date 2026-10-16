import Link from "next/link";
import type { Metadata } from "next";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { when } from "@/lib/format";
import { LOGIC_LABEL } from "@/lib/labels";
import { createClient } from "@/lib/supabase/server";
import { team, type TeamMember } from "@/lib/team";
import { Calendar } from "./Calendar";
import { Pools, type Pool } from "./Pools";
import { Rules, type Rule } from "./Rules";
import { Simulation, type SimRule } from "./Simulation";
import { QueuesView, type Queues } from "./Queues";
import { Week, type CalendarWeek } from "./Week";
import { Capacity, type CapacityData } from "./Capacity";
import { assignable } from "@/lib/team";
import { istDay } from "@/lib/format";
import { weekOf } from "@/lib/holidays";

export const metadata: Metadata = { title: "Lead Allocation" };

const TABS = [["rules", "Rules"], ["pools", "Pools"], ["calendar", "Hours and leave"], ["capacity", "Capacity"], ["simulation", "Simulation"], ["queues", "Queues"], ["audit", "Decisions"]] as const;
type Tab = (typeof TABS)[number][0];

/** Lead Allocation (spec B7): who gets each sales lead, and why. Rules run top to bottom; the first match decides. */
export default async function AllocationPage({ searchParams }: { searchParams: Promise<{ tab?: string; week?: string }> }) {
  const me = await requireUser("workspace", "/w/allocation");
  const sp = await searchParams;
  const asked = sp.tab;
  const tab: Tab = TABS.some(([k]) => k === asked) ? (asked as Tab) : "rules";
  const admin = me.role === "admin";
  const supabase = await createClient();
  let body: React.ReactNode;
  try {
    if (tab === "rules" || tab === "pools") {
      const [rules, pools, members, people] = await Promise.all([
        supabase.from("allocation_rules").select("id, position, name, enabled, condition, logic, params, pool_id, fallbacks, applies_from, is_catch_all").order("position").order("id"),
        supabase.from("pools").select("id, name, description").order("name"),
        supabase.from("pool_members").select("pool_id, user_id, weight, position").order("position"),
        team(),
      ]);
      const poolList: Pool[] = (pools.data ?? []).map((p) => ({ ...p, members: (members.data ?? []).filter((m) => m.pool_id === p.id) })) as Pool[];
      const persons = people.filter((p) => p.user.is_active).map((p) => ({ user_id: p.user.user_id, name: p.user.full_name ?? p.user.email, role: p.user.role }));
      body = tab === "rules"
        ? <Rules rules={(rules.data ?? []) as Rule[]} pools={poolList} admin={admin} />
        : <Pools pools={poolList} people={persons} admin={admin} />;
    } else if (tab === "calendar") {
      const from = weekOf(/^\d{4}-\d{2}-\d{2}$/.test(sp.week ?? "") ? sp.week! : istDay(new Date())).from;
      const [people, holidays, week] = await Promise.all([team(), supabase.from("holidays").select("day, name, kind").gte("day", istDay(new Date())).order("day").limit(30),
        rpc<CalendarWeek>("calendar_week", { p_from: from })]);
      const active = people.filter((p: TeamMember) => p.user.is_active && p.user.role !== "marketing");
      body = (
        <div className="stack">
          <Week w={week} admin={admin} people={assignable(people)} />
          <h2>Usual hours and leave</h2>
          <Calendar people={active} holidays={holidays.data ?? []} admin={admin} />
        </div>
      );
    } else if (tab === "capacity") {
      body = <Capacity c={await rpc<CapacityData>("capacity")} />;
    } else if (tab === "simulation") {
      const { data } = await supabase.from("allocation_rules").select("id, name, enabled, applies_from, is_catch_all").order("position").order("id");
      const now = new Date();
      const later = ((data ?? []) as (SimRule & { is_catch_all: boolean })[]).filter((r) => !r.is_catch_all && (!r.enabled || new Date(r.applies_from) > now));
      body = admin ? <Simulation rules={later} /> : <p className="note">Only the Admin runs simulations.</p>;
    } else if (tab === "queues") {
      const [queues, people] = await Promise.all([rpc<Queues>("queues"), team()]);
      body = <QueuesView queues={queues} people={assignable(people)} canAct={admin} />;
    } else {
      const { data } = await supabase.from("allocation_decisions").select("id, lead_id, at, trigger, hot, rule_name, logic, pool, eligible, skipped, chosen, outcome, why")
        .eq("simulated", false).order("at", { ascending: false }).limit(100);
      const people = await team();
      const name = (id: string | null) => people.find((p) => p.user.user_id === id)?.user.full_name ?? (id ? "—" : "");
      body = (
        <div className="table-wrap"><table>
          <thead><tr><th>When</th><th>Lead</th><th>Trigger</th><th>Rule · logic</th><th>Outcome</th><th>Skipped</th></tr></thead>
          <tbody>
            {(data ?? []).length === 0 && <tr><td colSpan={6} className="muted">No decisions yet.</td></tr>}
            {(data ?? []).map((d) => (
              <tr key={d.id}>
                <td className="nowrap">{when(d.at)}</td>
                <td><Link href={`/w/leads/${d.lead_id}`}>#{d.lead_id}</Link>{d.hot ? " · hot" : ""}</td>
                <td>{d.trigger}</td>
                <td>{d.rule_name ?? "—"}<div className="small muted">{LOGIC_LABEL[d.logic ?? ""] ?? d.logic ?? ""}{d.pool ? ` · ${d.pool}` : ""}</div></td>
                <td>{d.outcome === "assigned" || d.outcome === "kept" ? `${d.outcome === "kept" ? "Kept with" : "To"} ${name(d.chosen)}` : d.outcome.replace(/_/g, " ")}<div className="small muted">{d.why ?? ""}</div></td>
                <td className="small">{((d.skipped ?? []) as { name: string; why: string }[]).map((s) => `${s.name}: ${s.why}`).join("; ")}</td>
              </tr>
            ))}
          </tbody>
        </table></div>
      );
    }
  } catch (e) {
    body = <SetupError error={e} />;
  }
  return (
    <Page title="Lead Allocation" sub="Rules run top to bottom; the first that matches decides who gets the lead.">
      <div className="tabs" role="tablist">
        {TABS.map(([k, n]) => (
          <Link key={k} role="tab" aria-selected={tab === k} href={`/w/allocation?tab=${k}`}
            style={{ padding: "9px 12px", fontWeight: 600, textDecoration: "none", color: tab === k ? "var(--ink)" : "var(--muted)", borderBottom: `2px solid ${tab === k ? "var(--amber)" : "transparent"}` }}>{n}</Link>
        ))}
      </div>
      {body}
    </Page>
  );
}
