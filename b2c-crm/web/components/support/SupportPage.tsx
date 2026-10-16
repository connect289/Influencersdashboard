import Link from "next/link";
import { Page, SetupError, Empty } from "@/components/shell/Page";
import { rpc } from "@/lib/data";
import { when } from "@/lib/format";
import type { Me } from "@/lib/auth";
import { KIND_LABEL, ROLE_WORD, STATUS_LABEL } from "@/lib/support";
import { FileLink, NewTicketButton, ReplyBox, StatusControl } from "./SupportParts";

type Item = { id: number; number: string; kind: string; priority: string; subject: string; status: string; created_at: string; updated_at: string; developer_at: string | null;
  by: string; by_role: string; mine: boolean; messages: number; last: string | null; last_from: string | null };
type List = { counts: { open: number; ongoing: number; closed: number }; tickets: Item[] };
type Ticket = { id: number; number: string; kind: string; priority: string; subject: string; status: string; page: string | null; created_at: string; by: string; by_email: string; by_role: string; mine: boolean;
  messages: { id: number; author_kind: string; author: string | null; body: string; urls: string[]; attachments: { path: string; name: string; type: string }[]; status_to: string | null;
    created_at: string; mailed: boolean; mail_error: string | null }[] };

const CHIP: Record<string, string> = { open: "warm", in_progress: "soft", waiting: "risk", fixed: "ok", closed: "line" };
const GROUPS = [["open", "Open"], ["ongoing", "In progress"], ["closed", "Closed"], ["all", "All"]] as const;
const WHO: Record<string, string> = { user: "", admin: "Admin", developer: "Developer", system: "CRM" };

/**
 * Support (b31): raise a ticket, follow it under its number, see the developer's answers. Open, in progress (including
 * waiting for you and fixed) and closed tickets. The Admin sees everyone's tickets as well as their own.
 */
export async function SupportPage({ me, base, sp }: { me: Me; base: "/w" | "/s"; sp: { t?: string; g?: string; scope?: string; q?: string } }) {
  const admin = me.role === "admin";
  const scope = admin && sp.scope !== "mine" ? "all" : "mine";
  const group = GROUPS.some(([k]) => k === sp.g) ? sp.g! : "open";
  const t = Number(sp.t);
  const qs = (o: Record<string, string | undefined>) => `${base}/support?${new URLSearchParams(Object.entries({ g: group, scope: admin ? scope : undefined, q: sp.q, ...o }).filter(([, v]) => v) as [string, string][])}`;
  try {
    if (Number.isInteger(t) && t > 0) {
      const d = await rpc<Ticket>("support_get", { p_ticket: t });
      return (
        <Page title={`${d.number} · ${d.subject}`} sub={`${KIND_LABEL[d.kind] ?? d.kind} · raised by ${d.mine ? "you" : `${d.by} (${ROLE_WORD[d.by_role] ?? d.by_role})`} ${when(d.created_at)}`}
          back={<Link className="btn quiet sm" href={qs({ t: undefined })}>←</Link>}
          actions={<div className="row" style={{ gap: 6 }}><span className={`chip ${CHIP[d.status] ?? "line"}`}>{STATUS_LABEL[d.status] ?? d.status}</span>{d.priority === "urgent" && <span className="chip breach">Urgent</span>}
            {(d.mine || admin) && <StatusControl ticket={d.id} status={d.status} admin={admin} />}</div>}>
          <div className="stack">
            {d.status === "waiting" && d.mine && <div className="banner">The developer needs something from you: reply below.</div>}
            {d.status === "fixed" && d.mine && <div className="banner info"><div className="grow">The developer marked this fixed. Check it; close the ticket if it works, or reply if not. It closes by itself after 7 days.</div></div>}
            <div className="stack" style={{ gap: 8 }}>
              {d.messages.map((m) => (
                <article key={m.id} className="card pad stack" style={{ gap: 6, borderLeft: m.author_kind === "developer" ? "3px solid var(--amber)" : undefined }}>
                  <div className="row small" style={{ gap: 6 }}>
                    <b>{m.author_kind === "developer" ? "Developer" : m.author_kind === "system" ? "CRM" : m.author ?? "—"}</b>
                    {WHO[m.author_kind] && m.author_kind !== "developer" && m.author_kind !== "system" && <span className="chip line">{WHO[m.author_kind]}</span>}
                    <span className="muted">{when(m.created_at)}</span>
                    {m.status_to && <span className={`chip ${CHIP[m.status_to] ?? "line"}`}>→ {STATUS_LABEL[m.status_to] ?? m.status_to}</span>}
                    {admin && m.author_kind !== "developer" && m.author_kind !== "system" && <span className="muted">{m.mailed ? "emailed" : m.mail_error ? `not emailed: ${m.mail_error}` : "to be emailed"}</span>}
                  </div>
                  {m.body && <p style={{ whiteSpace: "pre-wrap" }}>{m.body}</p>}
                  {m.urls.length > 0 && <ul className="small" style={{ margin: 0, paddingLeft: 18 }}>{m.urls.map((u) => <li key={u}><a href={u} target="_blank" rel="noopener noreferrer">{u}</a></li>)}</ul>}
                  {m.attachments.length > 0 && <div className="row wrap" style={{ gap: 6 }}>{m.attachments.map((a) => <FileLink key={a.path} {...a} />)}</div>}
                </article>
              ))}
            </div>
            {(d.mine || admin) && <ReplyBox ticket={d.id} closed={d.status === "closed"} />}
          </div>
        </Page>
      );
    }
    const l = await rpc<List>("support_list", { p: { scope, group, q: sp.q ?? "" } });
    return (
      <Page title="Support" sub="Report a problem with the CRM, suggest a feature, or ask for a phone number change." actions={<NewTicketButton base={base} />}>
        <div className="stack">
          <div className="row wrap" style={{ gap: 6 }}>
            <div className="hscroll">
              {GROUPS.map(([k, n]) => (
                <Link key={k} className="pill" href={qs({ g: k })} aria-pressed={group === k} style={{ color: "inherit", textDecoration: "none" }}>
                  {n}{k !== "all" ? ` (${l.counts[k as "open" | "ongoing" | "closed"]})` : ""}
                </Link>
              ))}
            </div>
            <span className="grow" />
            {admin && <div className="hscroll">
              <Link className="pill" href={qs({ scope: "all" })} aria-pressed={scope === "all"} style={{ color: "inherit", textDecoration: "none" }}>Everyone&apos;s</Link>
              <Link className="pill" href={qs({ scope: "mine" })} aria-pressed={scope === "mine"} style={{ color: "inherit", textDecoration: "none" }}>Mine</Link>
            </div>}
            <form action={`${base}/support`} className="row" style={{ gap: 4 }}>
              <input type="hidden" name="g" value={group} />{admin && <input type="hidden" name="scope" value={scope} />}
              <input className="input" name="q" defaultValue={sp.q ?? ""} placeholder="SUP-0042 or words" aria-label="Search tickets" style={{ width: 180 }} />
            </form>
          </div>
          {l.tickets.length === 0 ? <Empty>No tickets here.</Empty> : (
            <div className="table-wrap"><table>
              <thead><tr><th>Ticket</th><th>Subject</th>{scope === "all" && <th>Raised by</th>}<th>Status</th><th>Last</th><th>Updated</th></tr></thead>
              <tbody>{l.tickets.map((x) => (
                <tr key={x.id} className="click">
                  <td className="mono"><Link href={qs({ t: String(x.id) })}>{x.number}</Link></td>
                  <td><Link href={qs({ t: String(x.id) })} className="plain">{x.subject}</Link>{x.priority === "urgent" && <span className="chip breach" style={{ marginLeft: 4 }}>Urgent</span>}
                    <div className="small muted">{KIND_LABEL[x.kind] ?? x.kind}</div></td>
                  {scope === "all" && <td>{x.by}<div className="small muted">{ROLE_WORD[x.by_role] ?? x.by_role}</div></td>}
                  <td><span className={`chip ${CHIP[x.status] ?? "line"}`}>{STATUS_LABEL[x.status] ?? x.status}</span></td>
                  <td className="small ellipsis" style={{ maxWidth: 260 }}>{x.last_from === "developer" ? <b>Developer: </b> : null}{x.last}</td>
                  <td className="small nowrap">{when(x.updated_at)}</td>
                </tr>
              ))}</tbody>
            </table></div>
          )}
        </div>
      </Page>
    );
  } catch (e) {
    return <Page title="Support"><SetupError error={e} /></Page>;
  }
}
