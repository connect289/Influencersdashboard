"use client";
import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { fromLocalInput } from "@/lib/format";
import type { Stage, SubStage } from "@/lib/types";
import { bulkJourney, bulkStage, deleteRequest, reassign, restoreLeads, routeToPartners, tagLeads, viewIds } from "../actions";

type Person = { user_id: string; name: string };
type Refused = { lead_id: number; why: string }[];
const DELETE_REASONS = ["junk", "test", "duplicate entry", "spam", "student request"];

/**
 * Bulk tools over the ticked rows, or every row of the view (spec B10.3). The Admin: reassign, tag, journeys, stage,
 * partner routing, export, delete (a background job with typed confirmation, undo for 30 days). Marketing: tags and
 * journeys. Each lead is checked as if done alone; refusals are listed by lead.
 */
export function BulkBar({ people, admin, recycle, total, query, journeys, stages, subs, exportQuery }: {
  people: Person[]; admin: boolean; recycle: boolean; total: number; query: Record<string, unknown>; journeys: { id: number; name: string }[];
  stages: Stage[]; subs: SubStage[]; exportQuery: string | null;
}) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [op, setOp] = useState<string>(recycle ? "restore" : admin ? "reassign" : "tag");
  const [to, setTo] = useState<string>("");
  const [text, setText] = useState("");
  const [reason, setReason] = useState(DELETE_REASONS[0]!);
  const [confirmText, setConfirmText] = useState("");
  const [journey, setJourney] = useState<number>(journeys[0]?.id ?? 0);
  const [stage, setStage] = useState<number>(stages[0]?.id ?? 1);
  const [sub, setSub] = useState("");
  const [due, setDue] = useState("");
  const [format, setFormat] = useState<"csv" | "xlsx">("xlsx");
  const [all, setAll] = useState<number[] | null>(null);
  const [ticked, setTicked] = useState(0);
  const [refused, setRefused] = useState<Refused>([]);

  useEffect(() => {
    const count = () => setTicked(document.querySelectorAll('input[form="bulk"][name="lead"]:checked').length);
    document.addEventListener("change", count);
    count();
    return () => document.removeEventListener("change", count);
  }, []);
  const queryKey = JSON.stringify(query);
  useEffect(() => { setAll(null); }, [queryKey]);

  const ticks = () => Array.from(document.querySelectorAll<HTMLInputElement>('input[form="bulk"][name="lead"]:checked')).map((i) => Number(i.value));
  const leads = () => all ?? ticks();
  const n = all ? all.length : ticked;
  const subsOf = subs.filter((s) => s.stage_id === stage);

  function selectAll() {
    start(async () => {
      const r = await viewIds(query);
      if (!r.ok) return void toast.error(r.error);
      setAll(r.data?.ids ?? []);
      toast.success(`All ${r.data?.total ?? 0} leads of this view are selected.`);
    });
  }

  function run() {
    const ls = leads();
    if (ls.length === 0) return void toast.error("Tick at least one lead.");
    if (op === "export") {
      const viaIds = !all || exportQuery === null;
      if (viaIds && ls.length > 500) return void toast.error("Export at most 500 ticked rows this way, or export the whole view from the Excel and CSV buttons.");
      const q = new URLSearchParams(exportQuery ?? "");
      q.set("format", format);
      if (viaIds) q.set("ids", ls.join(","));
      // a POST from this page (the export refuses links and other sites)
      const f = document.createElement("form");
      f.method = "post";
      f.action = "/w/leads/export";
      for (const [k, v] of q) {
        const input = document.createElement("input");
        input.type = "hidden";
        input.name = k;
        input.value = v;
        f.appendChild(input);
      }
      document.body.appendChild(f);
      f.submit();
      f.remove();
      return;
    }
    start(async () => {
      let msg: string | null = null;
      let error: string | null = null;
      let refusals: Refused = [];
      if (op === "reassign") {
        const r = await reassign(ls, to || null, text);
        if (r.ok) msg = `${r.data} reassigned.`; else error = r.error;
      } else if (op === "tag" || op === "untag") {
        const r = await tagLeads(ls, text, op === "tag");
        if (r.ok) msg = r.notice ?? "Done."; else error = r.error;
      } else if (op === "journey_add" || op === "journey_remove") {
        const r = await bulkJourney(ls, op === "journey_add" ? "add" : "remove", op === "journey_add" ? journey : null);
        if (r.ok) { msg = `${r.data?.done ?? 0} ${op === "journey_add" ? "added to the journey" : "taken out of their journey"}.`; refusals = r.data?.refused ?? []; } else error = r.error;
      } else if (op === "stage") {
        const r = await bulkStage(ls, stage, sub || null, text, due ? fromLocalInput(due) : null);
        if (r.ok) { msg = `${r.data?.done ?? 0} moved.`; refusals = r.data?.refused ?? []; } else error = r.error;
      } else if (op === "route") {
        const r = await routeToPartners(ls, text);
        if (r.ok) { msg = `${r.data?.sent ?? 0} sent to partner routing.`; refusals = r.data?.refused ?? []; } else error = r.error;
      } else if (op === "delete") {
        const r = await deleteRequest(ls, reason, confirmText);
        if (r.ok) msg = `Deleting ${r.data?.leads ?? ls.length} in the background. Undo under Background jobs for 30 days.`; else error = r.error;
      } else if (op === "restore") {
        const r = await restoreLeads(ls);
        if (r.ok) msg = `${r.data} restored.`; else error = r.error;
      }
      setRefused(refusals);
      if (error) return void toast.error(error);
      toast.success(msg ?? "Done.");
      if (refusals.length) toast.warning(`${refusals.length} not done: see the list under the bar.`);
      setText(""); setConfirmText(""); setAll(null);
      router.refresh();
    });
  }

  const needsText = op === "reassign" || op === "route" || op === "tag" || op === "untag";
  return (
    <div className="stack tight" style={{ position: "sticky", bottom: 0 }}>
      <form id="bulk" className="bulkbar" onSubmit={(e) => { e.preventDefault(); run(); }}>
        <b>{all ? `All ${all.length} in this view` : `${ticked} ticked`}:</b>
        {!recycle && (all
          ? <button type="button" className="btn ghost sm" onClick={() => setAll(null)}>Only the ticked rows</button>
          : total > ticked && <button type="button" className="btn ghost sm" onClick={selectAll} disabled={busy}>Select all {total} in this view</button>)}
        <select className="input" value={op} onChange={(e) => setOp(e.target.value)} aria-label="Action">
          {recycle ? <option value="restore">Restore</option> : (
            <>
              {admin && <option value="reassign">Reassign</option>}
              <option value="tag">Add a tag</option>
              <option value="untag">Remove a tag</option>
              <option value="journey_add">Add to a journey</option>
              <option value="journey_remove">Take out of their journey</option>
              {admin && <option value="stage">Change stage</option>}
              {admin && <option value="route">Send to partner routing</option>}
              {admin && <option value="export">Export</option>}
              {admin && <option value="delete">Delete</option>}
            </>
          )}
        </select>
        {op === "reassign" && (
          <select className="input" value={to} onChange={(e) => setTo(e.target.value)} aria-label="To">
            <option value="">Through the allocation rules</option>
            {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
          </select>
        )}
        {op === "journey_add" && (
          <select className="input" value={journey} onChange={(e) => setJourney(Number(e.target.value))} aria-label="Journey">
            {journeys.length === 0 && <option value={0}>No published journey</option>}
            {journeys.map((j) => <option key={j.id} value={j.id}>{j.name}</option>)}
          </select>
        )}
        {op === "stage" && (
          <>
            <select className="input" value={stage} onChange={(e) => { setStage(Number(e.target.value)); setSub(""); }} aria-label="Stage">
              {stages.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
            <select className="input" value={sub} onChange={(e) => setSub(e.target.value)} aria-label="Sub-stage">
              <option value="">Sub-stage…</option>
              {subsOf.map((s) => <option key={s.name} value={s.name}>{s.name}</option>)}
            </select>
            <input className="input" value={text} onChange={(e) => setText(e.target.value)} placeholder="Comment for all" aria-label="Comment" maxLength={300} />
            {stage !== 9 && stage !== 10 && <input className="input" type="datetime-local" value={due} onChange={(e) => setDue(e.target.value)} aria-label="Next follow-up (default: tomorrow)" title="Next follow-up (default: in a day)" />}
          </>
        )}
        {op === "export" && (
          <select className="input" value={format} onChange={(e) => setFormat(e.target.value as "csv" | "xlsx")} aria-label="Format">
            <option value="xlsx">Excel</option><option value="csv">CSV</option>
          </select>
        )}
        {op === "delete" && (
          <>
            <select className="input" value={reason} onChange={(e) => setReason(e.target.value)} aria-label="Reason">
              {DELETE_REASONS.map((r) => <option key={r}>{r}</option>)}
            </select>
            <input className="input" value={confirmText} onChange={(e) => setConfirmText(e.target.value)} placeholder={`Type DELETE ${n}`} aria-label={`Type DELETE ${n} to confirm`} autoComplete="off" />
          </>
        )}
        {needsText && (
          <input className="input" value={text} onChange={(e) => setText(e.target.value)} required minLength={op.includes("tag") ? 1 : 3}
            placeholder={op.includes("tag") ? "Tag" : "Reason (kept in the audit log)"} aria-label={op.includes("tag") ? "Tag" : "Reason"} maxLength={300} />
        )}
        <button className={`btn ${op === "delete" ? "danger" : "ghost"} sm`} type="submit" disabled={busy || (op === "delete" && confirmText.trim() !== `DELETE ${n}`)}>{busy ? "Working…" : "Apply"}</button>
      </form>
      {refused.length > 0 && (
        <div className="banner" role="status">
          <div className="grow small"><b>Not done for {refused.length}:</b> {refused.slice(0, 30).map((x) => `#${x.lead_id} (${x.why})`).join(" · ")}{refused.length > 30 ? ` and ${refused.length - 30} more` : ""}</div>
          <button type="button" className="btn quiet sm" onClick={() => setRefused([])}>Dismiss</button>
        </div>
      )}
    </div>
  );
}
