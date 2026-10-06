"use client";
import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Check, CircleAlert, LoaderCircle, RotateCcw, Search, SquarePen } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Badge } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { commissionText, inr, REVIEW_LABEL, REVIEW_TONE } from "@/lib/programmes";
import type { ProgrammeLabel, VersionRow } from "@/lib/programmes-data";
import { approveRows, reviewRow, searchCatalogue } from "../../../actions";

type Uni = { id: number; name: string; short_name: string | null };

function ProgrammeText({ p }: { p: ProgrammeLabel }) {
  return (
    <>
      <span className="block truncate text-[13px] text-fg" title={p.program_name}>{p.course} · {p.specialization}</span>
      <span className="block truncate text-[12px] text-subtle">{p.university_short || p.university} · {p.mode} · {p.level}{p.fee_total ? ` · ${inr(p.fee_total)}` : ""}</span>
    </>
  );
}

/** Pick a catalogue programme by hand: choose the university, filter by text. */
function ChooseDialog({ open, onClose, universities, onPick }: { open: boolean; onClose: () => void; universities: Uni[]; onPick: (id: number) => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const [uni, setUni] = useState<number | null>(null);
  const [q, setQ] = useState("");
  const [results, setResults] = useState<ProgrammeLabel[]>([]);
  const [pending, start] = useTransition();

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
  }, [open]);

  useEffect(() => {
    if (!open || (!uni && q.trim().length < 2)) { setResults([]); return; }
    const t = setTimeout(() => start(async () => setResults(await searchCatalogue(uni, q.trim()))), 250);
    return () => clearTimeout(t);
  }, [open, uni, q]);

  return (
    <dialog ref={ref} onClose={onClose} onClick={(e) => { if (e.target === ref.current) onClose(); }} aria-labelledby="choose-title"
      className="m-auto w-[min(640px,calc(100vw-2rem))] rounded-[var(--radius-card)] border border-border bg-surface p-0 text-fg shadow-2xl backdrop:bg-overlay backdrop:backdrop-blur-sm">
      <div className="border-b border-border p-5">
        <h2 id="choose-title" className="text-[15px] font-semibold">Choose the catalogue programme</h2>
        <div className="mt-3 flex flex-wrap gap-2">
          <select value={uni ?? ""} onChange={(e) => setUni(e.target.value ? Number(e.target.value) : null)} aria-label="University"
            className="h-9 min-w-0 flex-1 basis-56 rounded-lg border border-border bg-surface px-2.5 text-[13px] focus:border-ring focus:outline-none">
            <option value="">Any university</option>
            {universities.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
          </select>
          <div className="relative min-w-0 flex-1 basis-56">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-subtle" aria-hidden />
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Programme or specialization" aria-label="Search the catalogue" maxLength={100}
              className="h-9 w-full rounded-lg border border-border bg-surface pl-9 pr-3 text-[13px] focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30" />
          </div>
        </div>
      </div>
      <ul className="max-h-[50vh] divide-y divide-border overflow-y-auto">
        {pending && <li className="flex items-center gap-2 px-5 py-4 text-[13px] text-muted"><LoaderCircle className="size-4 animate-spin" /> Searching…</li>}
        {!pending && results.length === 0 && <li className="px-5 py-6 text-center text-[13px] text-muted">{uni || q.trim().length >= 2 ? "No programmes found." : "Pick a university or type at least two letters."}</li>}
        {!pending && results.map((p) => (
          <li key={p.id}>
            <button type="button" onClick={() => onPick(p.id)} className="block w-full px-5 py-2.5 text-left hover:bg-surface-hover"><ProgrammeText p={p} /></button>
          </li>
        ))}
      </ul>
      <div className="flex justify-end border-t border-border bg-surface-2/60 px-5 py-3">
        <Button variant="secondary" size="sm" onClick={onClose}>Cancel</Button>
      </div>
    </dialog>
  );
}

/** Rows of a version with their catalogue match; on a draft, every row can be approved, re-matched or ignored. */
export function ReviewTable({ versionId, rows, editable, universities }: { versionId: number; rows: VersionRow[]; editable: boolean; universities: Uni[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState<number | null>(null);
  const [choose, setChoose] = useState<number | null>(null);
  const [ignore, setIgnore] = useState<number | null>(null);
  const [request, setRequest] = useState<number | null>(null);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [bulk, startBulk] = useTransition();

  const act = async (rowId: number, action: string, programmeId?: number | null, reason?: string) => {
    setBusy(rowId);
    const err = await reviewRow(rowId, action, programmeId, reason);
    setBusy(null);
    if (err) { toast.error(err); return err; }
    setSelected((s) => { const n = new Set(s); n.delete(rowId); return n; });
    router.refresh();
  };

  const suggestible = rows.filter((r) => r.review_status === "needs_review" && r.programme);
  const strong = suggestible.filter((r) => (r.confidence ?? 0) >= 0.8).map((r) => r.id);
  const approveSelected = (ids: number[]) =>
    startBulk(async () => {
      const res = await approveRows(versionId, ids);
      if ("error" in res) { toast.error(res.error); return; }
      toast.success(`${res.approved} ${res.approved === 1 ? "match" : "matches"} approved`);
      setSelected(new Set());
      router.refresh();
    });

  if (rows.length === 0) return <p className="px-5 py-8 text-center text-[13px] text-muted">No rows in this view.</p>;

  return (
    <>
      {editable && suggestible.length > 0 && (
        <div className="flex flex-wrap items-center gap-2 border-b border-border bg-surface-2/50 px-4 py-2.5">
          <span className="text-[12.5px] text-muted">{selected.size ? `${selected.size} selected` : `${suggestible.length} suggested ${suggestible.length === 1 ? "match" : "matches"} to check`}</span>
          {selected.size > 0 && <Button size="sm" onClick={() => approveSelected([...selected])} disabled={bulk}>{bulk && <LoaderCircle className="size-3.5 animate-spin" />} Approve selected</Button>}
          {selected.size === 0 && strong.length > 0 && (
            <Button size="sm" variant="secondary" onClick={() => setSelected(new Set(strong))}>Select the {strong.length} strong {strong.length === 1 ? "suggestion" : "suggestions"} (80%+)</Button>
          )}
          {selected.size > 0 && <Button size="sm" variant="ghost" onClick={() => setSelected(new Set())}>Clear</Button>}
        </div>
      )}
      <div className="overflow-x-auto">
        <table className="w-full min-w-[980px] text-left text-[13px]">
          <thead className="text-[11px] uppercase tracking-wider text-subtle">
            <tr className="border-b border-border">
              {editable && <th scope="col" className="w-9 py-2.5 pl-4"><span className="sr-only">Select</span></th>}
              <th scope="col" className="w-14 px-3 py-2.5 font-medium">Row</th>
              <th scope="col" className="px-3 py-2.5 font-medium">In the partner&apos;s file</th>
              <th scope="col" className="px-3 py-2.5 font-medium">Catalogue match</th>
              <th scope="col" className="px-3 py-2.5 font-medium">Status</th>
              {editable && <th scope="col" className="px-4 py-2.5 text-right font-medium">Action</th>}
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {rows.map((r) => {
              const n = r.norm;
              const canSelect = editable && r.review_status === "needs_review" && r.programme;
              return (
                <tr key={r.id} className={cn("align-top", busy === r.id && "opacity-60")}>
                  {editable && (
                    <td className="w-9 py-3 pl-4">
                      {canSelect && <input type="checkbox" aria-label={`Select row ${r.row_no}`} checked={selected.has(r.id)} className="size-4 accent-[var(--primary)]"
                        onChange={() => setSelected((s) => { const x = new Set(s); if (x.has(r.id)) x.delete(r.id); else x.add(r.id); return x; })} />}
                    </td>
                  )}
                  <td className="tabular px-3 py-3 text-muted">{r.row_no}</td>
                  <td className="max-w-[340px] px-3 py-3">
                    <span className="block truncate text-fg">{[n.university, n.course, n.specialization].filter(Boolean).join(" · ") || "—"}</span>
                    <span className="block truncate text-[12px] text-subtle">
                      {[n.mode, n.level, n.programme_code, n.fees?.total ? inr(n.fees.total) : null, n.commission ? `Commission ${commissionText(n.commission)}` : null].filter(Boolean).join(" · ")}
                    </span>
                    {n.errors?.map((e) => <span key={e} className="mt-0.5 flex items-center gap-1 text-[12px] text-danger"><CircleAlert className="size-3" /> {e}</span>)}
                  </td>
                  <td className="max-w-[340px] px-3 py-3">
                    {r.programme ? <ProgrammeText p={r.programme} /> : <span className="text-subtle">{r.candidates.length ? "No confident match" : "Nothing similar in the catalogue"}</span>}
                    {editable && r.review_status !== "approved" && r.review_status !== "ignored" && r.candidates.length > 1 && (
                      <details className="mt-1">
                        <summary className="cursor-pointer text-[12px] text-info">Other close programmes</summary>
                        <ul className="mt-1 space-y-1">
                          {r.candidates.filter((c) => c.id !== r.programme?.id).map((c) => (
                            <li key={c.id}>
                              <button type="button" onClick={() => act(r.id, "match", c.id)} className="block w-full rounded-md px-2 py-1 text-left hover:bg-surface-hover">
                                <ProgrammeText p={c} />
                              </button>
                            </li>
                          ))}
                        </ul>
                      </details>
                    )}
                  </td>
                  <td className="px-3 py-3">
                    <Badge tone={REVIEW_TONE[r.review_status] ?? "neutral"}>{REVIEW_LABEL[r.review_status] ?? r.review_status}</Badge>
                    {r.match_method && r.review_status !== "ignored" && (
                      <span className="mt-1 block text-[11.5px] text-subtle">
                        {r.match_method === "previous" ? "As in an earlier file" : r.match_method === "exact" ? "Exact" : r.match_method === "manual" ? "Chosen by hand" : `Similar · ${Math.round((r.confidence ?? 0) * 100)}%`}
                      </span>
                    )}
                    {r.ignore_reason && <span className="mt-1 block max-w-[180px] text-[11.5px] text-subtle">{r.ignore_reason}</span>}
                  </td>
                  {editable && (
                    <td className="px-4 py-3">
                      <div className="flex flex-wrap justify-end gap-1">
                        {r.review_status === "needs_review" && r.programme && (
                          <Button size="sm" onClick={() => act(r.id, "approve")} disabled={busy === r.id}><Check className="size-3.5" /> Approve</Button>
                        )}
                        {r.review_status !== "ignored" && (
                          <Button size="sm" variant="secondary" onClick={() => setChoose(r.id)} disabled={busy === r.id}><SquarePen className="size-3.5" /> {r.programme ? "Change" : "Choose"}</Button>
                        )}
                        {(r.review_status === "needs_review" || r.review_status === "no_match") && (
                          <>
                            <Button size="sm" variant="ghost" onClick={() => setIgnore(r.id)} disabled={busy === r.id}>Ignore</Button>
                            {!r.requested && <Button size="sm" variant="ghost" onClick={() => setRequest(r.id)} disabled={busy === r.id}>Not in catalogue</Button>}
                          </>
                        )}
                        {(r.review_status === "approved" || r.review_status === "ignored") && r.match_method !== "previous" && (
                          <Button size="sm" variant="ghost" onClick={() => act(r.id, "reopen")} disabled={busy === r.id}><RotateCcw className="size-3.5" /> Undo</Button>
                        )}
                      </div>
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <ChooseDialog open={choose !== null} onClose={() => setChoose(null)} universities={universities}
        onPick={(id) => { const row = choose; setChoose(null); if (row) void act(row, "match", id); }} />
      <ConfirmDialog open={ignore !== null} onClose={() => setIgnore(null)} title="Ignore this row?" confirmLabel="Ignore row"
        reason={{ label: "Reason", placeholder: "e.g. heading row, discontinued, not sold through Eduwit" }}
        onConfirm={async (reason) => (ignore ? act(ignore, "ignore", null, reason) : undefined)}>
        The programme will not be offered through this partner. You can undo it before publishing.
      </ConfirmDialog>
      <ConfirmDialog open={request !== null} onClose={() => setRequest(null)} title="Not in Eduwit's catalogue?" confirmLabel="Request catalogue addition"
        onConfirm={async () => (request ? act(request, "request") : undefined)}>
        The row is set aside and listed as a catalogue request with the partner&apos;s details. Leads route only to catalogue programmes, so it is offered once the programme is added and the file is uploaded again.
      </ConfirmDialog>
    </>
  );
}
