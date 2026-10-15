import { inr } from "@/lib/format";
import type { LeadList } from "@/lib/types";
import { cellText, fieldDef } from "@/lib/viewFields";

/** The view grouped (b2c.lead_list group_by): leads per value over the whole view, with commission totals when the person may see money. */
export function GroupSummary({ groups, by, total }: { groups: NonNullable<LeadList["groups"]>; by: string; total: number }) {
  const money = groups.some((g) => g.expected !== undefined || g.commission !== undefined);
  const label = (k: string | null) => (k === null || k === "" ? "(not set)" : by === "stage" || by === "sub_stage" || by === "owner_name" ? k : cellText(by, fieldDef(by)?.type === "date" ? null : k));
  const sum = (k: "expected" | "commission") => groups.reduce((a, g) => a + Number(g[k] ?? 0), 0);
  return (
    <details className="panel" open>
      <summary>By {fieldDef(by)?.label.toLowerCase() ?? by} · {groups.length} groups</summary>
      <div className="table-wrap">
        <table>
          <thead><tr><th>{fieldDef(by)?.label ?? by}</th><th className="right">Leads</th><th className="right">Share</th>{money && <><th className="right">University commission</th><th className="right">Counsellor commission</th></>}</tr></thead>
          <tbody>
            {groups.map((g) => (
              <tr key={String(g.key)}>
                <td>{label(g.key)}</td><td className="right num">{g.count}</td><td className="right num">{total ? Math.round((g.count / total) * 100) : 0}%</td>
                {money && <><td className="right num">{inr(g.expected ?? 0)}</td><td className="right num">{inr(g.commission ?? 0)}</td></>}
              </tr>
            ))}
            {money && <tr><td><b>Total</b></td><td className="right num"><b>{groups.reduce((a, g) => a + g.count, 0)}</b></td><td /><td className="right num"><b>{inr(sum("expected"))}</b></td><td className="right num"><b>{inr(sum("commission"))}</b></td></tr>}
          </tbody>
        </table>
      </div>
      {groups.length === 100 && <p className="note">The 100 largest groups.</p>}
    </details>
  );
}
