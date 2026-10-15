import Link from "next/link";
import { Search } from "lucide-react";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import type { Me } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { initials, when } from "@/lib/format";
import { salesPeople, type Person } from "@/lib/people";
import { createClient } from "@/lib/supabase/server";
import type { Snippet } from "../snippet-actions";
import type { AppChoice } from "./Media";
import { Thread, type Compose } from "./Thread";

export type InboxParams = { lead?: string; q?: string; unread?: string; window?: string; awaiting?: string; owner?: string };

type Convo = {
  phone: string; lead_id: number | null; name: string | null; course: string | null; owner_id: string | null; owner_name: string | null; unread: number;
  window_open: boolean | null; last_at: string | null; last: string | null; last_template: string | null; last_direction: "in" | "out" | null;
  awaiting_reply: boolean; read_only: boolean; match: string | null;
};

/**
 * WhatsApp on the Eduwit B2C number (spec B8.5, B15) from b2c.inbox_list: counsellors their own leads, the sales head their
 * team, the Admin everyone, Marketing everyone read-only. Search covers name, number, message text and template name.
 */
export async function InboxView({ me, base, leadBase, sp }: { me: Me; base: string; leadBase: string; sp: InboxParams }) {
  const leadId = Number(sp.lead) || null;
  const filterOwner = me.role !== "counsellor";
  const owner = filterOwner && sp.owner && (sp.owner === "none" || /^[0-9a-f-]{36}$/i.test(sp.owner)) ? sp.owner : null;
  const win = sp.window === "open" || sp.window === "closed" ? sp.window : null;
  let list: Convo[];
  let compose: Compose | null = null;
  let snippets: Snippet[] = [];
  let people: Person[] = [];
  let apps: AppChoice[] = [];
  try {
    const supabase = await createClient();
    [list, compose, snippets, people, apps] = await Promise.all([
      rpc<Convo[]>("inbox_list", { p: { search: sp.q ?? "", unread: sp.unread === "1", window: win, awaiting: sp.awaiting === "1", owner } }),
      leadId ? rpc<Compose>("wa_compose", { p_lead: leadId }) : Promise.resolve(null),
      leadId && me.role !== "marketing" ? rpc<Snippet[]>("snippets_mine").catch(() => [] as Snippet[]) : Promise.resolve([] as Snippet[]),
      filterOwner ? salesPeople(me).catch(() => [] as Person[]) : Promise.resolve([] as Person[]),
      leadId ? supabase.from("applications").select("id, university, programme, checklist").eq("lead_id", leadId).not("status", "in", "(withdrawn,rejected)").order("created_at")
        .then((r) => (r.data ?? []) as AppChoice[]) : Promise.resolve([] as AppChoice[]),
    ]);
  } catch (e) {
    return <Page title="Inbox"><SetupError error={e} /></Page>;
  }
  const current = list.find((c) => c.lead_id === leadId);
  const readOnly = me.role === "marketing" || !!current?.read_only;
  const href = (o: Partial<InboxParams>) => {
    const u = new URLSearchParams();
    for (const [k, v] of Object.entries({ q: sp.q, unread: sp.unread, window: win ?? undefined, awaiting: sp.awaiting, owner: owner ?? undefined, ...o })) if (v) u.set(k, v);
    const q = u.toString();
    return q ? `${base}?${q}` : base;
  };
  const pill = (label: string, on: boolean, to: string) => <Link className="pill" href={to} aria-pressed={on} style={{ color: "inherit", textDecoration: "none" }}>{label}</Link>;
  const listing = (
    <div className="stack">
      <form className="search" action={base} role="search">
        <Search className="icon s" aria-hidden />
        {sp.unread && <input type="hidden" name="unread" value={sp.unread} />}
        {win && <input type="hidden" name="window" value={win} />}
        {sp.awaiting && <input type="hidden" name="awaiting" value={sp.awaiting} />}
        {owner && <input type="hidden" name="owner" value={owner} />}
        <input name="q" defaultValue={sp.q ?? ""} placeholder="Name, number, message or template" aria-label="Search conversations" />
      </form>
      <div className="hscroll">
        {pill("All", !sp.unread && !win && !sp.awaiting, href({ unread: undefined, window: undefined, awaiting: undefined }))}
        {pill("Unread", sp.unread === "1", href({ unread: sp.unread === "1" ? undefined : "1" }))}
        {pill("Awaiting reply", sp.awaiting === "1", href({ awaiting: sp.awaiting === "1" ? undefined : "1" }))}
        {pill("Window open", win === "open", href({ window: win === "open" ? undefined : "open" }))}
        {pill("Window closed", win === "closed", href({ window: win === "closed" ? undefined : "closed" }))}
      </div>
      {filterOwner && (
        <form action={base} className="row" style={{ gap: 6 }}>
          {sp.q && <input type="hidden" name="q" value={sp.q} />}
          {sp.unread && <input type="hidden" name="unread" value={sp.unread} />}
          {win && <input type="hidden" name="window" value={win} />}
          {sp.awaiting && <input type="hidden" name="awaiting" value={sp.awaiting} />}
          <select className="input grow" name="owner" defaultValue={owner ?? ""} aria-label="Counsellor">
            <option value="">{me.role === "sales_head" ? "My whole team" : "Every counsellor"}</option>
            <option value="none">Nobody (unassigned)</option>
            {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
          </select>
          <button className="btn ghost sm" type="submit">Show</button>
        </form>
      )}
      {list.length === 0 ? <Empty>{sp.q ? <>Nothing matches “{sp.q}”.</> : "No conversations here."}</Empty> : (
        <div className="list">
          {list.map((c) => (
            <Link key={c.phone} className="li" href={c.lead_id ? href({ lead: String(c.lead_id) }) : base} aria-current={c.lead_id === leadId ? "page" : undefined}>
              <span className="avatar">{initials(c.name)}</span>
              <span className="t ellipsis">{c.name ?? c.phone}</span>
              <span className="row" style={{ gap: 4 }}>{c.unread > 0 && <span className="chip hot">{c.unread}</span>}<span className="small muted">{when(c.last_at)}</span></span>
              <span className="s ellipsis">
                {c.window_open ? "● " : ""}{c.awaiting_reply ? "Waiting for you · " : ""}{filterOwner ? `${c.owner_name ?? "Unassigned"} · ` : ""}
                {c.match ? <>“…{c.match}…”</> : c.last_template && !c.last ? `Template ${c.last_template}` : c.last ?? ""}
              </span>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
  return (
    <Page title="Inbox" sub={me.role === "marketing" ? "Every WhatsApp conversation on the Eduwit B2C number, read-only" : me.role === "counsellor" ? "Your leads' WhatsApp on the Eduwit B2C number" : "WhatsApp on the Eduwit B2C number"}>
      <div className="grid" style={{ gridTemplateColumns: compose ? "minmax(240px, 340px) minmax(0, 1fr)" : "1fr", alignItems: "start" }}>
        <div className={compose ? "only-desk" : undefined}>{listing}</div>
        {compose && leadId && (
          <Thread leadId={leadId} name={current?.name ?? null} compose={compose} snippets={snippets} readOnly={readOnly} base={href({ lead: undefined })} leadBase={leadBase} apps={apps}
            vars={{ first_name: (current?.name ?? "").split(" ")[0] || null, programme: current?.course, counsellor_first_name: (me.full_name ?? "").split(" ")[0] || null }} />
        )}
      </div>
    </Page>
  );
}
