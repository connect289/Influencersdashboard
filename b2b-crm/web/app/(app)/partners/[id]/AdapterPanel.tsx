"use client";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Check, CircleDashed, Eye, LoaderCircle, Plus, RefreshCw, ScanSearch, ShieldCheck, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import { formatDateTime, relativeTime } from "@/lib/format";
import {
  DEDUPE_CONFIRM_HINT, DEDUPE_CONFIRM_LABEL, REFERENCE_HELP, SETTING_FIELD, adapterHoldMinutes, adapterProblems, holdWindowLabel, pollSummary, secretField,
  type AdapterPreview, type AdapterStatus, type Env,
} from "@/lib/adapters";
import { adapterAction, adapterPreview, saveAdapter } from "./adapter-actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";
const ENV_LABEL: Record<Env, string> = { live: "Live", sandbox: "Sandbox (test leads)" };

function initial(s: AdapterStatus, env: Env) {
  const e = s.envs[env];
  const st = e?.settings ?? {};
  return {
    settings: Object.fromEntries(s.spec.settings.map((k) => [k, String(st[k] ?? "")])),
    secrets: Object.fromEntries(s.spec.secrets.map((k) => [k, ""])) as Record<string, string>,
    reference_field: String(st.reference_field ?? ""), status_field: String(st.status_field ?? ""),
    poll: st.poll !== false, poll_minutes: st.poll_minutes ? String(st.poll_minutes) : "",
    fixed: Object.entries(st.fixed ?? {}).map(([k, v]) => ({ k, v: String(v) })),
  };
}

/** The stored answer to 'This CRM blocks duplicates on create'; null when the status read did not carry it (the key is then sent only once the Admin ticks or unticks). */
const storedDedupe = (s: AdapterStatus): boolean | null => (typeof s.dedupe_confirmed === "boolean" ? s.dedupe_confirmed : s.dedupe_confirmed_at ? true : s.dedupe_confirmed_at === null ? false : null);

/**
 * A CRM adapter's connection: settings and secrets per environment, the duplicate-blocking confirmation that sets the hold window
 * (D37), sign-in, polling, schema discovery and a push preview.
 */
export function AdapterPanel({ id, s }: { id: number; s: AdapterStatus }) {
  const router = useRouter();
  const [env, setEnv] = useState<Env>("live");
  const [f, setF] = useState(() => initial(s, "live"));
  // partner-wide (not per environment), so it survives an environment switch
  const [dedupe, setDedupe] = useState<boolean | null>(() => storedDedupe(s));
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [preview, setPreview] = useState<AdapterPreview | null>(null);
  const e = s.envs[env];
  const st = e?.state;
  const problems = useMemo(() => adapterProblems(s.spec, { ...f, secretsSet: e?.secrets_set ?? [] }), [s.spec, f, e?.secrets_set]);
  const confirmed = dedupe === true;

  const switchEnv = (v: Env) => { setEnv(v); setF(initial(s, v)); setError(null); setPreview(null); };
  const save = async () => {
    if (Object.keys(problems).length) { setError("Check the highlighted fields."); return; }
    setPending("save"); setError(null);
    try {
      const r = await saveAdapter(id, { env, ...f, dedupe_confirmed: dedupe });
      if (!r.ok) { setError(r.error); return; }
      toast.success(`${ENV_LABEL[env]} connection saved · ${holdWindowLabel(confirmed).toLowerCase()}`);
      setF((x) => ({ ...x, secrets: Object.fromEntries(Object.keys(x.secrets).map((k) => [k, ""])) }));
      router.refresh();
    } finally { setPending(null); }
  };
  const act = async (a: "schema" | "poll") => {
    setPending(a);
    try {
      const r = await adapterAction(id, env, a);
      if (!r.ok) toast.error(r.error);
      else toast.success(a === "poll" ? "Asked the CRM for changed leads; results within a minute" : "Asked the CRM for its fields; the snapshot appears in Mapping studio within a minute");
      router.refresh();
    } finally { setPending(null); }
  };
  const showPreview = async () => {
    setPending("preview");
    try { const r = await adapterPreview(id, env); if (r.ok) setPreview(r.data); else toast.error(r.error); } finally { setPending(null); }
  };

  return (
    <div className="space-y-4 px-5 py-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="inline-flex rounded-lg border border-border p-0.5" role="tablist" aria-label="Environment">
          {(["live", "sandbox"] as const).map((v) => (
            <button key={v} type="button" role="tab" aria-selected={env === v} onClick={() => switchEnv(v)}
              className={cn("rounded-md px-3 py-1 text-[12.5px] font-medium", env === v ? "bg-surface-2 text-fg" : "text-muted hover:text-fg")}>
              {ENV_LABEL[v]} {s.envs[v]?.configured ? <Check className="ml-0.5 inline size-3 text-success" /> : null}
            </button>
          ))}
        </div>
        {e?.configured ? <Badge tone="success">Connected</Badge> : <Badge><CircleDashed className="size-3" /> Not set up</Badge>}
      </div>
      {env === "sandbox" && <p className="text-[12px] text-muted">Test leads go only to the sandbox; real students only to live. Use the partner&apos;s sandbox org or a test account.</p>}

      <div className="grid gap-3 sm:grid-cols-2">
        {s.spec.settings.map((k) => {
          const d = SETTING_FIELD[k] ?? { label: k };
          const err = problems[`settings.${k}`];
          return (
            <label key={k} className="block space-y-1">
              <span className="text-[12.5px] font-medium text-fg">{d.label}{d.optional && <span className="font-normal text-subtle"> (optional)</span>}</span>
              {d.options ? (
                <select className={field} value={f.settings[k] ?? ""} aria-invalid={Boolean(err)} onChange={(x) => setF({ ...f, settings: { ...f.settings, [k]: x.target.value } })}>
                  <option value="" disabled>Choose…</option>
                  {d.options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
                </select>
              ) : (
                <input className={cn(field, "font-mono text-[12.5px]")} value={f.settings[k] ?? ""} placeholder={d.placeholder} aria-invalid={Boolean(err)}
                  onChange={(x) => setF({ ...f, settings: { ...f.settings, [k]: x.target.value } })} />
              )}
              {err ? <span className="block text-xs text-danger">{err}</span> : d.hint && <span className="block text-xs text-muted">{d.hint}</span>}
            </label>
          );
        })}
        {s.spec.secrets.map((k) => {
          const d = secretField(s.adapter, k);
          if (s.adapter === "inhouse" && f.settings.auth_type === "none") return null;
          const set = e?.secrets_set.includes(k) ?? false;
          const err = problems[`secrets.${k}`];
          return (
            <label key={k} className="block space-y-1">
              <span className="flex items-center justify-between gap-2 text-[12.5px] font-medium text-fg">{d.label}
                {set ? <Badge tone="success"><Check className="size-3" /> Set</Badge> : <Badge><CircleDashed className="size-3" /> Not set</Badge>}</span>
              <input type="password" autoComplete="off" spellCheck={false} className={field} value={f.secrets[k] ?? ""}
                placeholder={set ? "Leave empty to keep it" : ""} aria-invalid={Boolean(err)}
                onChange={(x) => setF({ ...f, secrets: { ...f.secrets, [k]: x.target.value } })} />
              {err ? <span className="block text-xs text-danger">{err}</span> : <span className="block text-xs text-muted">{d.hint}</span>}
            </label>
          );
        })}
      </div>

      <div className={cn("space-y-2 rounded-lg border px-3 py-2.5 text-[12.5px]", confirmed ? "border-success/25 bg-success-bg/40" : "border-border")}>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <label className="flex items-start gap-2 font-medium text-fg">
            <input type="checkbox" className="mt-0.5 accent-[var(--primary)]" checked={confirmed} onChange={(x) => setDedupe(x.target.checked)} />
            <span>{DEDUPE_CONFIRM_LABEL}</span>
          </label>
          <Badge tone={confirmed ? "success" : "neutral"}>{confirmed && <ShieldCheck className="size-3" />} {holdWindowLabel(confirmed)}</Badge>
        </div>
        <p className="text-muted">
          {DEDUPE_CONFIRM_HINT}. {confirmed
            ? "A duplicate then comes back in the create call itself, so the lead moves to the next partner at once."
            : `Eduwit waits ${adapterHoldMinutes(false)} minutes for a duplicate or rejection before the lead counts as accepted and the student is told.`}
          {" "}Applies to live and sandbox alike; saved with either.
        </p>
        {dedupe !== storedDedupe(s) ? (
          <p className="text-warning">Not saved yet: the hold window changes when you save.</p>
        ) : s.dedupe_confirmed_at ? (
          <p className="text-subtle">Confirmed <span title={formatDateTime(s.dedupe_confirmed_at)}>{relativeTime(s.dedupe_confirmed_at)}</span>.</p>
        ) : null}
      </div>

      <details className="rounded-lg border border-border px-3 py-2 text-[12.5px]">
        <summary className="cursor-pointer font-medium text-fg">Fields and polling</summary>
        <div className="mt-3 space-y-3">
          <p className="text-muted">{REFERENCE_HELP[s.adapter]} Mapping studio&apos;s outbound fields are sent too and win over these defaults.</p>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block space-y-1"><span className="font-medium text-fg">Eduwit reference field</span>
              <input className={cn(field, "font-mono text-[12.5px]")} value={f.reference_field} placeholder={s.spec.reference_field} aria-invalid={Boolean(problems.reference_field)}
                onChange={(x) => setF({ ...f, reference_field: x.target.value })} />
              {problems.reference_field && <span className="block text-xs text-danger">{problems.reference_field}</span>}</label>
            <label className="block space-y-1"><span className="font-medium text-fg">Status field</span>
              <input className={cn(field, "font-mono text-[12.5px]")} value={f.status_field} placeholder={s.spec.status_field} aria-invalid={Boolean(problems.status_field)}
                onChange={(x) => setF({ ...f, status_field: x.target.value })} />
              {problems.status_field && <span className="block text-xs text-danger">{problems.status_field}</span>}</label>
          </div>
          {s.spec.poll && s.adapter === "inhouse" && !(f.settings.poll_url ?? "").trim() ? (
            <p className="text-muted">Add a changed-leads address above to poll this CRM. Without one, status comes by webhook (the events address on this page) or from the partner&apos;s export in Sync &amp; SLAs.</p>
          ) : s.spec.poll ? (
            <div className="flex flex-wrap items-end gap-3">
              <label className="flex items-center gap-2"><input type="checkbox" className="accent-[var(--primary)]" checked={f.poll} onChange={(x) => setF({ ...f, poll: x.target.checked })} />
                Poll the CRM for changes</label>
              <label className="block w-36 space-y-1"><span className="text-muted">every (minutes)</span>
                <input className={field} inputMode="numeric" value={f.poll_minutes} placeholder={env === "live" ? "15" : "2"} aria-invalid={Boolean(problems.poll_minutes)}
                  onChange={(x) => setF({ ...f, poll_minutes: x.target.value.replace(/\D/g, "") })} /></label>
              <span className="text-muted">Empty: live polls every sync interval (15 minutes, to save the partner&apos;s API calls), the sandbox every 2 minutes while testing. Webhooks can run as well.</span>
            </div>
          ) : <p className="text-muted">{s.spec.label} reports changes by webhook only (the events address on this page).</p>}
          <div className="space-y-1.5">
            <p className="font-medium text-fg">Fixed values <span className="font-normal text-muted">sent with every lead (for example an owner or a lead source the partner wants)</span></p>
            {f.fixed.map((x, i) => (
              <div key={i} className="flex gap-2">
                <input className={cn(field, "min-w-0 font-mono text-[12.5px]")} value={x.k} placeholder="CRM field" aria-label="CRM field"
                  onChange={(v) => setF({ ...f, fixed: f.fixed.map((y, j) => (j === i ? { ...y, k: v.target.value } : y)) })} />
                <input className={cn(field, "min-w-0")} value={x.v} placeholder="value" aria-label="Value"
                  onChange={(v) => setF({ ...f, fixed: f.fixed.map((y, j) => (j === i ? { ...y, v: v.target.value } : y)) })} />
                <Button variant="ghost" size="icon" aria-label="Remove" onClick={() => setF({ ...f, fixed: f.fixed.filter((_, j) => j !== i) })}><Trash2 className="size-4" /></Button>
              </div>
            ))}
            <Button size="sm" variant="secondary" onClick={() => setF({ ...f, fixed: [...f.fixed, { k: "", v: "" }] })}><Plus className="size-3.5" /> Add a fixed value</Button>
          </div>
        </div>
      </details>

      {error && <Notice tone="error">{error}</Notice>}
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-wrap gap-1.5">
          <Button size="sm" variant="secondary" onClick={showPreview} disabled={Boolean(pending)}>{pending === "preview" ? <LoaderCircle className="size-3.5 animate-spin" /> : <Eye className="size-3.5" />} Preview a push</Button>
          {e?.configured && s.spec.poll && <Button size="sm" variant="secondary" onClick={() => act("poll")} disabled={Boolean(pending) || st?.polling}>{pending === "poll" ? <LoaderCircle className="size-3.5 animate-spin" /> : <RefreshCw className="size-3.5" />} Poll now</Button>}
          {e?.configured && s.spec.schema && <Button size="sm" variant="secondary" onClick={() => act("schema")} disabled={Boolean(pending) || st?.fetching_schema}>{pending === "schema" ? <LoaderCircle className="size-3.5 animate-spin" /> : <ScanSearch className="size-3.5" />} Fetch fields</Button>}
        </div>
        <Button size="sm" onClick={save} disabled={Boolean(pending)}>{pending === "save" && <LoaderCircle className="size-3.5 animate-spin" />} Save {env}</Button>
      </div>

      {e?.configured && (
        <dl className="grid gap-x-4 gap-y-1.5 rounded-lg bg-surface-2/60 px-3 py-2.5 text-[12.5px] sm:grid-cols-[auto_1fr]">
          {s.spec.oauth && (<>
            <dt className="text-muted">Sign-in</dt>
            <dd className={st?.token_error ? "text-danger" : "text-fg"}>
              {st?.token_valid ? <>Signed in{st.token_expires_at && <>, renews {relativeTime(st.token_expires_at)}</>}</> : st?.token_error ?? "Signs in at the first push or poll"}
              {st?.instance_url && <span className="ml-1.5 font-mono text-[11.5px] text-subtle">{st.instance_url}</span>}
            </dd>
          </>)}
          {s.spec.poll && (<>
            <dt className="text-muted">Last poll</dt>
            <dd className={st?.last_poll_error ? "text-danger" : "text-fg"}>
              {st?.polling ? "Waiting for the CRM…" : st?.last_poll_at ? <span title={formatDateTime(st.last_poll_at)}>{relativeTime(st.last_poll_at)}</span> : "Not yet"}
              {st?.last_poll_error ? <> · {st.last_poll_error}</> : st?.last_poll_result && <> · {pollSummary(st.last_poll_result)}</>}
            </dd>
          </>)}
          {s.spec.schema && (<>
            <dt className="text-muted">Fields fetched</dt>
            <dd className={st?.last_schema_error ? "text-danger" : "text-fg"}>
              {st?.fetching_schema ? "Waiting for the CRM…" : st?.last_schema_at ? <span title={formatDateTime(st.last_schema_at)}>{relativeTime(st.last_schema_at)}</span> : "Not yet"}
              {st?.last_schema_error && <> · {st.last_schema_error}</>}
              {env === "live" && <span className="text-muted"> · checked daily for changes (drift)</span>}
            </dd>
          </>)}
          <dt className="text-muted">Polled events, 7 days</dt><dd className="tabular text-fg">{s.polled_events_7d}</dd>
          <dt className="text-muted">Hold window</dt>
          <dd className="text-fg">{adapterHoldMinutes(storedDedupe(s))} min{storedDedupe(s) ? " (CRM confirmed to block duplicates on create)" : " (duplicates may arrive after the create call)"}</dd>
        </dl>
      )}

      {preview && (
        <div className="space-y-1.5 rounded-lg border border-border p-3 text-[12px]">
          <p className="font-medium text-fg">What {preview.sample ? "a sample student" : <span className="font-mono">{preview.reference}</span>} would send</p>
          {preview.error && <p className="text-danger">{preview.error}</p>}
          {preview.url && <p className="break-all font-mono text-muted">POST {preview.url}</p>}
          <pre className="max-h-72 overflow-auto rounded bg-surface-2 p-2 font-mono text-[11px] text-fg">{JSON.stringify({ headers: preview.headers, body: preview.body }, null, 2)}</pre>
          <p className="text-subtle">Credentials are masked here. The student&apos;s budget, lead source, campaign and score are never sent.</p>
        </div>
      )}
    </div>
  );
}
