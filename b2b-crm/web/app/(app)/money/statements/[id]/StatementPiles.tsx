"use client";
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Download, ListChecks, LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Badge, Card, EmptyState } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { toCsv } from "@/lib/intake";
import { ENROLLMENT_STATUS, MATCH_METHOD, MATCH_STATUS, dayLabel, formatInr, type StatementDetail, type StatementLine } from "@/lib/money";
import { download } from "../../../intake/ui";
import { resolveLine, verifyMatched } from "../../actions";

type Pile = "matched" | "amount_mismatch" | "partner_only" | "eduwit_only";
const PILES: Pile[] = ["matched", "amount_mismatch", "partner_only", "eduwit_only"];

export function StatementPiles({ d }: { d: StatementDetail }) {
  const router = useRouter();
  const counts: Record<Pile, number> = { matched: d.counts.matched, amount_mismatch: d.counts.amount_mismatch, partner_only: d.counts.partner_only, eduwit_only: d.eduwit_only.length };
  const [pile, setPile] = useState<Pile>(PILES.find((p) => p !== "matched" && counts[p] > 0) ?? "matched");
  const [busy, setBusy] = useState<number | null>(null);
  const [dismiss, setDismiss] = useState<number | null>(null);
  const [bulk, setBulk] = useState(false);
  const lines = d.lines.filter((l) => l.match_status === pile);

  const act = async (l: StatementLine, action: "verify" | "record") => {
    setBusy(l.id);
    try {
      const r = await resolveLine(l.id, action, "");
      if (!r.ok) toast.error(r.error); else { toast.success(action === "verify" ? "Enrolment verified from the statement" : "Enrolment recorded; verify it to book the commission"); router.refresh(); }
    } finally { setBusy(null); }
  };
  const exportPile = () => {
    const rows = pile === "eduwit_only"
      ? d.eduwit_only.map((e) => ({ reference: e.reference, partner_record_id: e.record_id, name: e.name, programme: e.programme, enrolled_on: e.enrolled_on, eduwit_commission_net: e.eduwit_amount_inr }))
      : lines.map((l) => ({ row: l.row_no, reference: l.reference, partner_record_id: l.record_id, name: l.name, programme: l.programme, enrolled_on: l.enrolled_on,
                            partner_amount: l.amount_inr, eduwit_commission_net: l.eduwit_amount_inr, difference: l.diff_inr, resolution: l.resolution, note: l.resolution_note }));
    if (rows.length === 0) { toast.info("This pile is empty"); return; }
    download(`statement-${d.statement.id}-${pile}.csv`, toCsv(rows, Object.keys(rows[0]!)));
  };

  return (
    <Card className="min-w-0">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-5 py-3">
        <div className="flex flex-wrap gap-1.5" role="tablist" aria-label="Piles">
          {PILES.map((p) => (
            <button key={p} type="button" role="tab" aria-selected={pile === p} onClick={() => setPile(p)}
              className={cn("rounded-md border px-2.5 py-1 text-[12.5px]", pile === p ? "border-border-strong bg-surface-2 font-medium text-fg" : "border-transparent text-muted hover:text-fg")}>
              {MATCH_STATUS[p].label} <span className="tabular text-subtle">{counts[p]}</span>
            </button>
          ))}
        </div>
        <div className="flex gap-2">
          {d.counts.to_verify > 0 && <Button size="sm" onClick={() => setBulk(true)}><ListChecks className="size-3.5" /> Verify {d.counts.to_verify} matched</Button>}
          <Button size="sm" variant="secondary" onClick={exportPile}><Download className="size-3.5" /> Export this pile</Button>
        </div>
      </div>
      <p className="border-b border-border px-5 py-2 text-[12.5px] text-muted">{MATCH_STATUS[pile].hint}</p>

      {pile === "eduwit_only" ? (
        d.eduwit_only.length === 0 ? <EmptyState icon={ListChecks} title="Nothing missing">Every Eduwit enrolment in the period is on the statement.</EmptyState> : (
          <ul className="divide-y divide-border">
            {d.eduwit_only.map((e) => (
              <li key={e.enrollment_id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-2.5 text-[12.5px]">
                <Link href={`/leads?lead=${e.lead_id}`} className="font-medium text-fg hover:underline">{e.name ?? `Lead #${e.lead_id}`}</Link>
                <span className="font-mono text-subtle">{e.reference}</span>
                <span className="text-muted">{e.programme}</span>
                <span className="text-muted">enrolled {dayLabel(e.enrolled_on)}</span>
                <Badge tone={ENROLLMENT_STATUS[e.status].tone}>{ENROLLMENT_STATUS[e.status].label}</Badge>
                <span className="tabular ml-auto text-fg">{formatInr(e.eduwit_amount_inr)}</span>
              </li>
            ))}
          </ul>
        )
      ) : lines.length === 0 ? (
        <EmptyState icon={ListChecks} title="Nothing in this pile" />
      ) : (
        <div className="relative overflow-x-auto">
          <table className="w-full min-w-[860px] text-left text-[12.5px]">
            <thead className="text-[11px] uppercase tracking-wider text-subtle">
              <tr className="border-b border-border">
                <th scope="col" className="px-5 py-2 font-medium">Row</th>
                <th scope="col" className="px-3 py-2 font-medium">Student</th>
                <th scope="col" className="px-3 py-2 font-medium">Matched by</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">Partner says</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">Eduwit (net)</th>
                <th scope="col" className="px-3 py-2 font-medium">Enrolment</th>
                <th scope="col" className="px-5 py-2"><span className="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {lines.map((l) => (
                <tr key={l.id} className="align-top">
                  <td className="tabular px-5 py-2.5 text-subtle">{l.row_no}</td>
                  <td className="px-3 py-2.5">
                    {l.lead_id ? <Link href={`/leads?lead=${l.lead_id}`} className="font-medium text-fg hover:underline">{l.name ?? `Lead #${l.lead_id}`}</Link> : <span className="text-fg">{l.name ?? "—"}</span>}
                    <span className="block font-mono text-[11.5px] text-subtle">{[l.reference, l.record_id, l.phone].filter(Boolean).join(" · ")}</span>
                    {l.programme && <span className="block text-[11.5px] text-muted">{l.programme}{l.enrolled_on && ` · ${dayLabel(l.enrolled_on)}`}</span>}
                  </td>
                  <td className="px-3 py-2.5 text-muted">{l.match_method ? MATCH_METHOD[l.match_method] : "No Eduwit lead"}</td>
                  <td className="tabular px-3 py-2.5 text-right text-fg">{formatInr(l.amount_inr)}</td>
                  <td className="tabular px-3 py-2.5 text-right text-fg">{formatInr(l.eduwit_amount_inr)}
                    {l.diff_inr !== null && <span className={cn("block text-[11px]", l.diff_inr < 0 ? "text-danger" : "text-warning")}>{l.diff_inr > 0 ? "+" : ""}{formatInr(l.diff_inr)}</span>}</td>
                  <td className="px-3 py-2.5">{l.enrollment_status ? <Badge tone={ENROLLMENT_STATUS[l.enrollment_status].tone}>{ENROLLMENT_STATUS[l.enrollment_status].label}</Badge> : <span className="text-subtle">none</span>}</td>
                  <td className="whitespace-nowrap px-5 py-2.5 text-right">
                    {l.resolution ? <span className="text-[12px] text-muted">{l.resolution}{l.resolution_note && `: ${l.resolution_note}`}</span> : <>
                      {busy === l.id && <LoaderCircle className="mr-2 inline size-3.5 animate-spin" />}
                      {l.enrollment_status === "reported" && <Button size="sm" onClick={() => act(l, "verify")} disabled={busy !== null}>Verify</Button>}
                      {!l.enrollment_id && l.allocation_id && <Button size="sm" onClick={() => act(l, "record")} disabled={busy !== null}>Record enrolment</Button>}
                      <Button size="sm" variant="ghost" onClick={() => setDismiss(l.id)} disabled={busy !== null}>Dismiss</Button>
                    </>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <ConfirmDialog open={dismiss !== null} onClose={() => setDismiss(null)} title="Dismiss this line?" confirmLabel="Dismiss"
        reason={{ label: "Why", placeholder: "e.g. not an Eduwit student; agreed with the partner" }}
        onConfirm={async (note) => { const r = await resolveLine(dismiss!, "dismiss", note); if (!r.ok) return r.error; toast.success("Dismissed"); router.refresh(); }} />
      <ConfirmDialog open={bulk} onClose={() => setBulk(false)} title={`Verify ${d.counts.to_verify} matched enrolments?`} confirmLabel="Verify all"
        onConfirm={async () => {
          const r = await verifyMatched(d.statement.id);
          if (!r.ok) return r.error;
          toast.success(`${r.data.verified} verified${r.data.errors.length ? `, ${r.data.errors.length} need a look (${r.data.errors[0]!.error})` : ""}`);
          router.refresh();
        }}>
        <p className="text-[13px] text-muted">Each statement line becomes the proof for its enrolment, and the commission is booked at the statement&apos;s enrolment date.</p>
      </ConfirmDialog>
    </Card>
  );
}
