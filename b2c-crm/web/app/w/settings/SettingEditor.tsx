"use client";
import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { settingSave } from "../actions";

type Scalar = string | number | boolean | null;
const isScalar = (v: unknown): v is Scalar => v === null || ["string", "number", "boolean"].includes(typeof v);
const label = (k: string) => k.replace(/_/g, " ").replace(/\bpct\b/, "%").replace(/\binr\b/i, "₹").replace(/\busd\b/i, "$").replace(/\bist\b/i, "IST");

/**
 * One setting as a form: a field per value (switch, number or text; a list as comma-separated words), and the parts
 * that are nested as JSON. "Edit as JSON" shows the whole thing. Every save needs a reason and becomes a new version.
 */
export function SettingEditor({ k, value }: { k: string; value: unknown }) {
  const router = useRouter();
  const initial = useMemo(() => JSON.stringify(value, null, 2), [value]);
  const obj = value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
  const [mode, setMode] = useState<"form" | "json">(obj ? "form" : "json");
  const [text, setText] = useState(initial);
  const [draft, setDraft] = useState<Record<string, unknown>>(obj ?? {});
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();

  const current = (): unknown => {
    if (mode === "json") return JSON.parse(text);
    return draft;
  };
  const dirty = mode === "json" ? text !== initial : JSON.stringify(draft) !== JSON.stringify(obj);
  const reset = () => { setText(initial); setDraft(obj ?? {}); setError(null); };
  const save = () => {
    let parsed: unknown;
    try { parsed = current(); } catch { return setError("That is not valid JSON."); }
    start(async () => {
      const r = await settingSave(k, parsed, reason);
      if (!r.ok) return setError(r.error);
      setError(null); setReason("");
      toast.success("Saved as a new version.");
      router.refresh();
    });
  };
  const set = (key: string, v: unknown) => setDraft((d) => ({ ...d, [key]: v }));

  return (
    <div className="stack" style={{ gap: 8 }}>
      {mode === "form" && obj ? (
        <div className="setting-form">
          {Object.entries(draft).map(([key, v]) => {
            const orig = obj[key];
            if (typeof orig === "boolean") {
              return <label key={key} className="checkbox"><input type="checkbox" checked={!!v} onChange={(e) => set(key, e.target.checked)} /> {label(key)}</label>;
            }
            if (typeof orig === "number" || (orig === null && typeof v === "number")) {
              return <label key={key} className="field"><span>{label(key)}</span><input className="input num" type="number" step="any" value={v === null ? "" : String(v)} onChange={(e) => set(key, e.target.value === "" ? null : Number(e.target.value))} /></label>;
            }
            if (isScalar(orig)) {
              return <label key={key} className="field"><span>{label(key)}</span><input className="input" value={v === null ? "" : String(v)} onChange={(e) => set(key, e.target.value === "" ? null : e.target.value)} placeholder="empty" /></label>;
            }
            if (Array.isArray(orig) && orig.every(isScalar)) {
              return <label key={key} className="field"><span>{label(key)} (comma-separated)</span>
                <input className="input" value={(v as Scalar[]).map(String).join(", ")} onChange={(e) => set(key, e.target.value.split(",").map((s) => s.trim()).filter(Boolean).map((s) => (orig.length && typeof orig[0] === "number" && s !== "" && !Number.isNaN(Number(s)) ? Number(s) : s)))} /></label>;
            }
            return <label key={key} className="field" style={{ gridColumn: "1 / -1" }}><span>{label(key)} (JSON)</span>
              <textarea className="input mono" rows={Math.min(8, JSON.stringify(v, null, 2).split("\n").length + 1)} defaultValue={JSON.stringify(v, null, 2)}
                onChange={(e) => { try { set(key, JSON.parse(e.target.value)); setError(null); } catch { setError(`${label(key)}: not valid JSON yet.`); } }} spellCheck={false} /></label>;
          })}
        </div>
      ) : (
        <textarea className="input mono" value={text} onChange={(e) => setText(e.target.value)} rows={Math.min(16, initial.split("\n").length + 1)} aria-label={`${k} value`} spellCheck={false} />
      )}
      <div className="row wrap">
        {dirty && <>
          <input className="input grow" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Reason for the change (required)" aria-label="Reason" maxLength={300} />
          <button type="button" className="btn primary sm" onClick={save} disabled={busy || reason.trim().length < 3}>{busy ? "Saving…" : "Save"}</button>
          <button type="button" className="btn quiet sm" onClick={reset}>Undo</button>
        </>}
        {obj && !dirty && <button type="button" className="btn quiet sm" style={{ marginLeft: "auto" }} onClick={() => { setMode(mode === "form" ? "json" : "form"); reset(); }}>{mode === "form" ? "Edit as JSON" : "Edit as a form"}</button>}
      </div>
      {error && <p className="error" role="alert">{error}</p>}
    </div>
  );
}
