import Link from "next/link";
import { rpc } from "@/lib/data";
import { when } from "@/lib/format";

type Audit = {
  rows: { id: number; at: string; actor: string | null; actor_id: string | null; action: string; lead_id: number | null; detail: Record<string, unknown> }[];
  total: number; actions: string[]; people: { user_id: string; name: string }[];
};
type SignIns = { rows: { id: number; at: string; email: string | null; method: string; outcome: string; ip: string | null; user_agent: string | null }[]; failed_24h: number; outcomes: string[] };

const ACTION_LABEL: Record<string, string> = {
  phone_reveal: "Phone revealed", call_tap: "Call tapped", export: "Export", view_as_sales: "Viewed as Sales", contact_copy: "Number copied",
  contact_edit: "Contact edited", delete: "Lead deleted", recording_play: "Recording played", wa_bulk: "Template to several leads", settings: "Setting changed",
};

/** The audit log (spec B18): every phone reveal, Call tap, export, "view as Sales", contact edit and delete, filterable. */
export async function AuditPanel({ sp }: { sp: Record<string, string | undefined> }) {
  const limit = 100;
  const page = Math.max(0, Number(sp.page ?? 0) || 0);
  const a = await rpc<Audit>("audit_list", { p: { action: sp.action || null, actor: sp.actor || null, lead: sp.lead || null, from: sp.from ? `${sp.from}T00:00:00+05:30` : null, to: sp.to ? `${sp.to}T23:59:59+05:30` : null, limit, offset: page * limit } });
  const qs = (o: Record<string, string | number | undefined>) => {
    const q = new URLSearchParams({ tab: "audit" });
    for (const [k, v] of Object.entries({ action: sp.action, actor: sp.actor, lead: sp.lead, from: sp.from, to: sp.to, ...o })) if (v !== undefined && v !== "") q.set(k, String(v));
    return `/w/settings?${q}`;
  };
  return (
    <div className="stack">
      <form className="row wrap" action="/w/settings" style={{ gap: 6 }}>
        <input type="hidden" name="tab" value="audit" />
        <select className="input" name="action" defaultValue={sp.action ?? ""} style={{ width: "auto" }} aria-label="Action">
          <option value="">Every action</option>
          {a.actions.map((x) => <option key={x} value={x}>{ACTION_LABEL[x] ?? x}</option>)}
        </select>
        <select className="input" name="actor" defaultValue={sp.actor ?? ""} style={{ width: "auto" }} aria-label="Person">
          <option value="">Everyone</option>
          {a.people.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
        </select>
        <input className="input" name="lead" defaultValue={sp.lead ?? ""} placeholder="Lead #" inputMode="numeric" style={{ width: 110 }} aria-label="Lead" />
        <input className="input" name="from" type="date" defaultValue={sp.from ?? ""} style={{ width: "auto" }} aria-label="From" />
        <input className="input" name="to" type="date" defaultValue={sp.to ?? ""} style={{ width: "auto" }} aria-label="To" />
        <button className="btn ghost sm" type="submit">Filter</button>
        <span className="small muted">{a.total} entries</span>
      </form>
      <div className="table-wrap">
        <table>
          <thead><tr><th>When</th><th>Who</th><th>What</th><th>Lead</th><th>Detail</th></tr></thead>
          <tbody>
            {a.rows.length === 0 && <tr><td colSpan={5} className="muted">Nothing logged for this filter.</td></tr>}
            {a.rows.map((r) => (
              <tr key={r.id}>
                <td className="small mono">{when(r.at)}</td>
                <td>{r.actor ?? <span className="muted">system</span>}</td>
                <td>{ACTION_LABEL[r.action] ?? r.action}</td>
                <td>{r.lead_id ? <Link href={`/w/leads/${r.lead_id}`}>#{r.lead_id}</Link> : "—"}</td>
                <td className="small muted mono ellipsis" style={{ maxWidth: 360 }}>{Object.keys(r.detail ?? {}).length ? JSON.stringify(r.detail) : ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {a.total > limit && (
        <div className="pager">
          {page > 0 && <Link className="btn ghost sm" href={qs({ page: page - 1 })}>Previous</Link>}
          <span className="muted">{page * limit + 1}–{Math.min(a.total, (page + 1) * limit)} of {a.total}</span>
          {(page + 1) * limit < a.total && <Link className="btn ghost sm" href={qs({ page: page + 1 })}>Next</Link>}
        </div>
      )}
    </div>
  );
}

/** Every sign-in attempt (spec B3.2), newest first; failures in the last day are counted at the top. */
export async function SignInsPanel({ sp }: { sp: Record<string, string | undefined> }) {
  const s = await rpc<SignIns>("sign_in_list", { p: { outcome: sp.outcome || null, email: sp.email || null, limit: 200 } });
  return (
    <div className="stack">
      <form className="row wrap" action="/w/settings" style={{ gap: 6 }}>
        <input type="hidden" name="tab" value="signins" />
        <select className="input" name="outcome" defaultValue={sp.outcome ?? ""} style={{ width: "auto" }} aria-label="Outcome">
          <option value="">Every outcome</option>
          {s.outcomes.map((x) => <option key={x} value={x}>{x.replace(/_/g, " ")}</option>)}
        </select>
        <input className="input" name="email" type="email" defaultValue={sp.email ?? ""} placeholder="Email" style={{ width: 220 }} aria-label="Email" />
        <button className="btn ghost sm" type="submit">Filter</button>
        <span className={`chip ${s.failed_24h > 0 ? "risk" : "ok"}`}>{s.failed_24h} failed in 24 h</span>
      </form>
      <div className="table-wrap">
        <table>
          <thead><tr><th>When</th><th>Email</th><th>Method</th><th>Outcome</th><th>From</th></tr></thead>
          <tbody>
            {s.rows.length === 0 && <tr><td colSpan={5} className="muted">No sign-ins logged for this filter.</td></tr>}
            {s.rows.map((r) => (
              <tr key={r.id}>
                <td className="small mono">{when(r.at)}</td>
                <td>{r.email ?? "—"}</td>
                <td className="small">{r.method.replace(/_/g, " ")}</td>
                <td><span className={`chip ${["ok", "code_sent", "trusted"].includes(r.outcome) ? "ok" : "risk"}`}>{r.outcome.replace(/_/g, " ")}</span></td>
                <td className="small muted ellipsis" style={{ maxWidth: 320 }}>{r.ip ?? ""}{r.user_agent ? ` · ${r.user_agent}` : ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
