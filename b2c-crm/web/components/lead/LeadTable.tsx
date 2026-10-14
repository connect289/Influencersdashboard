import Link from "next/link";
import { BarChip, SlaChip, TempChip, TestChip } from "@/components/lead/Chips";
import { initials, when } from "@/lib/format";
import { reasonLabel } from "@/lib/labels";
import type { LeadRow } from "@/lib/types";

/** Leads as a table on a desktop and as a list on a phone. `base` is /s/leads or /w/leads. */
export function LeadTable({ rows, base, showOwner, select }: { rows: LeadRow[]; base: string; showOwner?: boolean; select?: boolean }) {
  return (
    <>
      <div className="table-wrap only-desk">
        <table>
          <thead>
            <tr>
              {select && <th aria-label="Select" />}
              <th>Student</th><th>Programme</th><th>Stage · sub-stage</th><th>Why with us</th>{showOwner && <th>Counsellor</th>}
              <th>Next follow-up</th><th>SLA</th><th className="right">Score</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((l) => (
              <tr key={l.lead_id}>
                {select && <td><input type="checkbox" className="sel" name="lead" value={l.lead_id} aria-label={`Select ${l.name ?? l.lead_id}`} form="bulk" /></td>}
                <td>
                  <Link href={`${base}/${l.lead_id}`} style={{ fontWeight: 600 }}>{l.name ?? `Lead #${l.lead_id}`}</Link>{" "}
                  <TempChip t={l.temperature} /> <TestChip on={l.is_test} />
                  <div className="small muted">{l.city ?? ""}{l.city && l.language ? " · " : ""}{l.language ?? ""}</div>
                </td>
                <td>{l.course ?? "—"}<div className="small muted">{l.university ?? ""}</div></td>
                <td>{l.status === "active" ? `${l.stage ?? "—"}${l.sub_stage ? " · " + l.sub_stage : ""}` : l.status === "pool" ? "Nurture pool" : `Closed · ${l.closed_reason ?? ""}`}</td>
                <td className="small">{reasonLabel(l.handoff_reason)} <BarChip reason={l.partner_bar_reason} /></td>
                {showOwner && <td>{l.owner_name ?? <span className="chip risk">Unassigned</span>}</td>}
                <td className="nowrap">{when(l.next_task_due_at)}</td>
                <td><SlaChip lead={l} /></td>
                <td className="right num">{l.score ?? "—"}</td>
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
            <span><TempChip t={l.temperature} /></span>
            <span className="s ellipsis">{l.course ?? "—"} · {l.stage ?? ""}{l.sub_stage ? " · " + l.sub_stage : ""} · next {when(l.next_task_due_at)}</span>
          </Link>
        ))}
      </div>
    </>
  );
}
