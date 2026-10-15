"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { ClipboardCheck } from "lucide-react";
import { toast } from "sonner";
import { qualifyRecord } from "@/app/s/actions";
import { QUESTIONS, questionsFor, type QuestionKey } from "@/lib/qualify";

const MORE: QuestionKey[] = ["course", "highest_qualification", "enrollment_timeline", "annual_budget_inr", "study_mode", "specialization", "email", "name"];

/**
 * "Collect the missing details" (spec B6.3, b39): a re-engaged lead that is not qualified is not sold to. The counsellor
 * given the To qualify task (or the Admin) records what is missing; the B2B CRM then routes the lead again.
 */
export function QualifyPanel({ leadId, missing, known }: { leadId: number; missing: string[] | null; known: Partial<Record<QuestionKey, string | null>> }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [extra, setExtra] = useState(false);
  const asked = questionsFor(missing);
  const keys = extra ? [...asked, ...MORE.filter((k) => !asked.includes(k))] : asked;
  const save = (f: FormData) => start(async () => {
    const answers: Record<string, string> = {};
    for (const k of keys) answers[k] = String(f.get(k) ?? "");
    const r = await qualifyRecord(leadId, answers);
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Recorded.");
    router.refresh();
  });
  return (
    <section className="panel">
      <header><h3><ClipboardCheck className="icon s" aria-hidden /> Collect the missing details</h3></header>
      <div className="body">
        <p className="note">Call only to collect these details. Once recorded they go to the B2B CRM, which routes the lead again; the lead is not sold to here.</p>
        <form className="stack" action={save}>
          {keys.map((k) => {
            const q = QUESTIONS[k];
            return (
              <label key={k} className="field"><span>{q.staffLabel}</span>
                {q.type === "select" ? (
                  <select className="input" name={k} defaultValue={known[k] ?? ""}>
                    <option value="">—</option>
                    {q.options!.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                    {known[k] && !q.options!.some(([v]) => v === known[k]) && <option value={known[k]!}>{known[k]}</option>}
                  </select>
                ) : <input className="input" name={k} type={q.type} defaultValue={known[k] ?? ""} maxLength={200} placeholder={q.placeholder} />}
              </label>
            );
          })}
          {!extra && <button type="button" className="btn quiet sm" style={{ justifySelf: "start" }} onClick={() => setExtra(true)}>More details</button>}
          <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Saving…" : "Record and send for routing"}</button>
        </form>
      </div>
    </section>
  );
}
