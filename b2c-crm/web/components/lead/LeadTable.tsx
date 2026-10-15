import Link from "next/link";
import { BarChip, FlagChip, SlaChip, TempChip, TestChip, UntouchedChip } from "@/components/lead/Chips";
import { initials, when } from "@/lib/format";
import { LANE_LABEL, OUTCOME_LABEL, reasonLabel } from "@/lib/labels";
import type { LeadRow } from "@/lib/types";
import { cellText, DEFAULT_COLUMNS, fieldDef } from "@/lib/viewFields";

const RIGHT = new Set(["number"]);

/** One cell of the table: a few columns are composed (student, stage, partner, calls); the rest render by type. */
function Cell({ c, l, base }: { c: string; l: LeadRow; base: string }) {
  const r = l as unknown as Record<string, unknown>;
  switch (c) {
    case "name":
      return (
        <td>
          <Link href={`${base}/${l.lead_id}`} style={{ fontWeight: 600 }}>{l.name ?? `Lead #${l.lead_id}`}</Link>{" "}
          <TempChip t={l.temperature} /> <TestChip on={l.is_test} /> <FlagChip flag={l.flagged} /> <UntouchedChip lead={l} />
          <div className="small muted">{l.city ?? ""}{l.city && l.language ? " · " : ""}{l.language ?? ""}</div>
        </td>
      );
    case "course": return <td>{l.course ?? "—"}<div className="small muted">{l.university ?? ""}</div></td>;
    case "stage":
      return <td>{l.status === "active" ? `${l.stage ?? "—"}${l.sub_stage ? " · " + l.sub_stage : ""}` : l.status === "pool" ? "Nurture pool" : `Closed · ${l.closed_reason ?? ""}`}</td>;
    case "handoff_reason": return <td className="small">{reasonLabel(l.handoff_reason)} <BarChip reason={l.partner_bar_reason} /></td>;
    case "lane": return <td className="small">{LANE_LABEL[l.lane ?? ""] ?? "—"}<div className="muted">{reasonLabel(l.handoff_reason)}</div></td>;
    case "owner_name": return <td>{l.owner_name ?? <span className="chip risk">Unassigned</span>}</td>;
    case "sla_status": return <td><SlaChip lead={l} /></td>;
    case "partner":
      return (
        <td className="small">{l.partner ?? "—"}
          {(l.partner_lost_reason || l.partners_tried_count) ? <div className="muted">{[l.partner_lost_reason, l.partners_tried_count ? `${l.partners_tried_count} tried` : ""].filter(Boolean).join(" · ")}</div> : null}
        </td>
      );
    case "calls_logged":
      return <td className="small"><span className="num">{l.calls_logged ?? 0}</span>{l.last_call_outcome ? <div className="muted">last: {OUTCOME_LABEL[l.last_call_outcome] ?? l.last_call_outcome}{l.last_call_at ? `, ${when(l.last_call_at)}` : ""}</div> : null}</td>;
    case "tags": return <td>{(l.tags ?? []).length ? l.tags.map((t) => <span key={t} className="chip line" style={{ marginRight: 4 }}>{t}</span>) : "—"}</td>;
    case "flagged": return <td>{l.flagged ? <FlagChip flag={l.flagged} /> : "—"}</td>;
    default: {
      const d = fieldDef(c);
      const date = d?.type === "date";
      return <td className={`${RIGHT.has(d?.type ?? "") ? "right num" : ""}${date ? " nowrap" : ""}`}>{cellText(c, r[c])}</td>;
    }
  }
}

/**
 * Leads as a table on a desktop and as a list on a phone. `base` is /s/leads or /w/leads. `columns` come from the view
 * (else the standard set); money columns show only when `money` (Admin and Marketing: the database strips them otherwise).
 */
export function LeadTable({ rows, base, showOwner, select, columns, money }: { rows: LeadRow[]; base: string; showOwner?: boolean; select?: boolean; columns?: string[]; money?: boolean }) {
  const cols = (columns?.length ? columns : DEFAULT_COLUMNS).filter((c) => fieldDef(c) && (money || !fieldDef(c)!.money) && (showOwner || c !== "owner_name"));
  return (
    <>
      <div className="table-wrap only-desk">
        <table>
          <thead>
            <tr>
              {select && <th aria-label="Select" />}
              {cols.map((c) => <th key={c} className={RIGHT.has(fieldDef(c)?.type ?? "") ? "right" : undefined}>{c === "stage" ? "Stage · sub-stage" : fieldDef(c)?.label ?? c}</th>)}
            </tr>
          </thead>
          <tbody>
            {rows.map((l) => (
              <tr key={l.lead_id} data-row>
                {select && <td><input type="checkbox" className="sel" name="lead" value={l.lead_id} aria-label={`Select ${l.name ?? l.lead_id}`} form="bulk" /></td>}
                {cols.map((c) => <Cell key={c} c={c} l={l} base={base} />)}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="list only-phone">
        {rows.map((l) => (
          <Link key={l.lead_id} href={`${base}/${l.lead_id}`} className="li">
            <span className="avatar">{initials(l.name)}</span>
            <span className="t ellipsis">{l.name ?? `Lead #${l.lead_id}`}</span>
            <span><TempChip t={l.temperature} /> <FlagChip flag={l.flagged} /> <UntouchedChip lead={l} /></span>
            <span className="s ellipsis">{l.course ?? "—"} · {l.stage ?? ""}{l.sub_stage ? " · " + l.sub_stage : ""} · next {when(l.next_task_due_at)}</span>
          </Link>
        ))}
      </div>
    </>
  );
}
