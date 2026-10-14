import Link from "next/link";
import { date, inr } from "@/lib/format";
import { calcText, LINE_STATUS, RATE_SOURCE, rateText, type CommissionLine } from "@/lib/money";

/**
 * Counsellor commission lines (spec B11.2). Every line shows the programme, each partner considered with its rate and
 * what it came to, and which one was used, so anyone can check the number without asking.
 */
export function CommissionLines({ lines, leadHref, showCounsellor, names, actions }: {
  lines: CommissionLine[]; leadHref: (id: number) => string; showCounsellor?: boolean; names?: Map<string, string>;
  actions?: (l: CommissionLine) => React.ReactNode;
}) {
  if (!lines.length) return <p className="note">No lines.</p>;
  return (
    <div className="table-wrap"><table>
      <thead><tr>
        <th>Student</th>{showCounsellor && <th>Counsellor</th>}<th>Programme</th><th>Enrolled</th><th>Rate</th><th>Status</th><th className="right">Amount</th>{actions && <th />}
      </tr></thead>
      <tbody>{lines.map((l) => {
        const st = LINE_STATUS[l.status] ?? { label: l.status, chip: "line" };
        return (
          <tr key={l.id}>
            <td><Link href={leadHref(l.lead_id)}>{l.student ?? `#${l.lead_id}`}</Link>{l.kind !== "booking" && <div className="small muted">{l.kind}{l.reason ? `: ${l.reason}` : ""}</div>}</td>
            {showCounsellor && <td>{names?.get(l.counsellor_id) ?? "—"}</td>}
            <td>{l.programme ?? "—"}<div className="small muted">{l.university ?? ""}</div></td>
            <td className="nowrap">{date(l.enrolled_on)}</td>
            <td style={{ minWidth: 220 }}>
              {l.kind === "booking" ? <RateDetail l={l} /> : <span className="small muted">{RATE_SOURCE[l.rate_source ?? ""] ?? l.rate_source ?? "—"}</span>}
            </td>
            <td><span className={`chip ${st.chip}`}>{st.label}</span>{l.flagged && <span className="chip breach" style={{ marginLeft: 4 }}>flagged</span>}
              {l.status === "provisional" && l.expected_settlement && <div className="small muted">settles about {date(l.expected_settlement)}</div>}
              {l.status === "confirmed" && l.due_on && <div className="small muted">due {date(l.due_on)}</div>}</td>
            <td className="right num">{inr(l.amount)}{l.tds ? <div className="small muted">TDS {inr(l.tds)}</div> : null}</td>
            {actions && <td>{actions(l)}</td>}
          </tr>
        );
      })}</tbody>
    </table></div>
  );
}

function RateDetail({ l }: { l: CommissionLine }) {
  const used = l.rate_used?.partner_id;
  return (
    <details>
      <summary className="small">{l.status === "needs_rate" ? "No rate found" : calcText(l.rate, inr)} <span className="muted">· {RATE_SOURCE[l.rate_source ?? ""] ?? l.rate_source}</span></summary>
      <div className="stack small" style={{ gap: 3, marginTop: 6 }}>
        <span className="muted">Fee {inr(l.fee)} · base {inr(l.base)}</span>
        {l.partners.length === 0 ? <span className="muted">No active partner offers this programme.</span> : l.partners.map((p) => (
          <span key={p.partner_id}>
            {p.partner_id === used ? <b>{p.name} (used)</b> : p.name}: {p.rate ? rateText(p.rate, inr) : "no rate"}
            {p.computed ? <span className="muted"> → {inr(p.computed.amount)}</span> : null}
            {p.offers_programme === false ? <span className="muted"> (does not offer it)</span> : null}
          </span>
        ))}
        {l.override && <span>Override: {rateText(l.override as never, inr)}</span>}
      </div>
    </details>
  );
}
