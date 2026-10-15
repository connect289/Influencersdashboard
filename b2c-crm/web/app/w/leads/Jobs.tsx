"use client";
import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { Download, Undo2 } from "lucide-react";
import { toast } from "sonner";
import { date, when } from "@/lib/format";
import { bulkJobUndo, exportLink } from "../actions";

export type BulkJob = { id: number; kind: string; leads: number; reason: string | null; status: string; done_count: number; result: { deleted?: number; kept?: number };
  by: string | null; created_at: string; done_at: string | null; undo_until: string | null };
export type ExportRow = { id: number; format: "csv" | "xlsx"; status: string; rows: number | null; created_at: string; expires_at: string | null; error: string | null };

const JOB_STATUS: Record<string, string> = { queued: "Waiting", running: "Running", done: "Done", undone: "Undone", failed: "Failed" };

/** Bulk deletes run in the background (b2c.bulk_jobs_list); each can be undone for 30 days. */
export function JobsPanel({ jobs, open }: { jobs: BulkJob[]; open: boolean }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const undo = (j: BulkJob) => {
    if (!confirm(`Restore the ${j.result.deleted ?? j.leads} leads this job deleted?`)) return;
    start(async () => {
      const r = await bulkJobUndo(j.id);
      if (!r.ok) return void toast.error(r.error);
      toast.success(r.notice ?? "Restored.");
      router.refresh();
    });
  };
  return (
    <details className="panel" open={open} id="jobs">
      <summary>Background jobs ({jobs.length})</summary>
      {jobs.length === 0 ? <p className="note">No bulk delete yet.</p> : (
        <div className="table-wrap"><table>
          <thead><tr><th>Job</th><th>Reason</th><th>Status</th><th className="right">Leads</th><th>Result</th><th>By</th><th /></tr></thead>
          <tbody>{jobs.map((j) => (
            <tr key={j.id}>
              <td>Delete #{j.id}<div className="small muted">{when(j.created_at)}</div></td>
              <td>{j.reason ?? "—"}</td>
              <td><span className={`chip ${j.status === "done" ? "ok" : j.status === "failed" ? "breach" : "line"}`}>{JOB_STATUS[j.status] ?? j.status}</span>{j.status === "running" && <div className="small muted">{j.done_count} of {j.leads}</div>}</td>
              <td className="right num">{j.leads}</td>
              <td className="small">{j.result.deleted ?? 0} deleted{j.result.kept ? `, ${j.result.kept} kept (an enrolment)` : ""}</td>
              <td className="small">{j.by ?? "—"}</td>
              <td>{j.undo_until && new Date(j.undo_until) > new Date() && (
                <button type="button" className="btn quiet sm" disabled={busy} onClick={() => undo(j)} title={`Until ${date(j.undo_until)}`}><Undo2 className="icon s" aria-hidden />Undo</button>
              )}</td>
            </tr>
          ))}</tbody>
        </table></div>
      )}
    </details>
  );
}

const EXPORT_STATUS: Record<string, string> = { queued: "Waiting", running: "Being written", ready: "Ready", failed: "Failed", expired: "Expired" };

/** The person's exports (b2c.exports_mine): large ones are written in the background; the link works for 7 days. */
export function ExportsPanel({ rows, open }: { rows: ExportRow[]; open: boolean }) {
  const [busy, start] = useTransition();
  const download = (x: ExportRow) => start(async () => {
    const r = await exportLink(x.id);
    if (!r.ok || !r.data) return void toast.error(r.ok ? "The file could not be opened." : r.error);
    window.location.href = r.data;
  });
  return (
    <details className="panel" open={open} id="exports">
      <summary>Exports ({rows.length})</summary>
      {rows.length === 0 ? <p className="note">Exports over 10,000 rows are written in the background and listed here.</p> : (
        <div className="table-wrap"><table>
          <thead><tr><th>Export</th><th>Status</th><th className="right">Rows</th><th>Link works until</th><th /></tr></thead>
          <tbody>{rows.map((x) => (
            <tr key={x.id}>
              <td>#{x.id} · {x.format === "xlsx" ? "Excel" : "CSV"}<div className="small muted">{when(x.created_at)}</div></td>
              <td><span className={`chip ${x.status === "ready" ? "ok" : x.status === "failed" ? "breach" : "line"}`}>{EXPORT_STATUS[x.status] ?? x.status}</span>{x.error && <div className="small error">{x.error}</div>}</td>
              <td className="right num">{x.rows ?? "—"}</td>
              <td className="small">{x.status === "ready" ? when(x.expires_at) : "—"}</td>
              <td>{x.status === "ready" && <button type="button" className="btn ghost sm" disabled={busy} onClick={() => download(x)}><Download className="icon s" aria-hidden />Download</button>}</td>
            </tr>
          ))}</tbody>
        </table></div>
      )}
    </details>
  );
}
