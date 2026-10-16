"use client";
import { useState, useTransition } from "react";
import { QUESTIONS, type QuestionKey } from "@/lib/qualify";
import { qualifySubmit } from "./actions";

/** Three quick questions, one tap each where possible; a thank-you once sent. */
export function QualifyForm({ token, questions, known }: { token: string; questions: QuestionKey[]; known: Partial<Record<QuestionKey, string>> }) {
  const [busy, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  if (done) {
    return (
      <div className="stack">
        <h2>Thank you</h2>
        <p className="muted">We have your answers. An Eduwit counsellor will suggest programmes that fit you, usually within a working day.</p>
      </div>
    );
  }
  return (
    <form className="stack" action={(f) => start(async () => {
      const answers: Record<string, string> = {};
      for (const k of questions) answers[k] = String(f.get(k) ?? "");
      const r = await qualifySubmit(token, answers);
      if (!r.ok) return setError(r.error ?? "That did not go through.");
      setDone(true);
    })}>
      {questions.map((k) => {
        const q = QUESTIONS[k];
        return (
          <label key={k} className="field"><span>{q.label}</span>
            {q.type === "select" ? (
              <select className="input" name={k} defaultValue={known[k] && q.options!.some(([v]) => v === known[k]) ? known[k] : ""} required={k === questions[0]}>
                <option value="" disabled>Choose…</option>
                {q.options!.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
              </select>
            ) : (
              <>
                <input className="input" name={k} type={q.type} defaultValue={known[k] ?? ""} maxLength={200} placeholder={q.placeholder} list={q.suggest ? `${k}-list` : undefined}
                  autoComplete={k === "email" ? "email" : k === "name" ? "name" : "off"} required={k === questions[0]} />
                {q.suggest && <datalist id={`${k}-list`}>{q.suggest.map((s) => <option key={s} value={s} />)}</datalist>}
              </>
            )}
          </label>
        );
      })}
      {error && <p className="error" role="alert">{error}</p>}
      <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Sending…" : "Send"}</button>
      <p className="small muted">Your answers go only to Eduwit, to suggest the right programme. Reply STOP on WhatsApp at any time to stop messages.</p>
    </form>
  );
}
