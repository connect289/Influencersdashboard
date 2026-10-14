"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { settingSave } from "../actions";

/** One setting as JSON, checked before it is sent; the database validates the shape too. */
export function SettingEditor({ k, value }: { k: string; value: unknown }) {
  const router = useRouter();
  const initial = JSON.stringify(value, null, 2);
  const [text, setText] = useState(initial);
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const save = () => {
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      return setError("That is not valid JSON.");
    }
    start(async () => {
      const r = await settingSave(k, parsed, reason);
      if (!r.ok) return setError(r.error);
      setError(null);
      setReason("");
      toast.success("Saved as a new version.");
      router.refresh();
    });
  };
  return (
    <div className="stack" style={{ gap: 6 }}>
      <textarea className="input mono" value={text} onChange={(e) => setText(e.target.value)} rows={Math.min(14, initial.split("\n").length + 1)} aria-label={`${k} value`} spellCheck={false} />
      {text !== initial && (
        <div className="row wrap">
          <input className="input grow" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Reason for the change (required)" aria-label="Reason" maxLength={300} />
          <button type="button" className="btn primary sm" onClick={save} disabled={busy || reason.trim().length < 3}>{busy ? "Saving…" : "Save"}</button>
          <button type="button" className="btn quiet sm" onClick={() => { setText(initial); setError(null); }}>Undo</button>
        </div>
      )}
      {error && <p className="error" role="alert">{error}</p>}
    </div>
  );
}
