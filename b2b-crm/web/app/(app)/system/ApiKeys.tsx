"use client";
import { useEffect, useRef, useState } from "react";
import { KeyRound, LoaderCircle, Plus } from "lucide-react";
import { toast } from "sonner";
import { Badge, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { formatDateTime, relativeTime } from "@/lib/format";
import { DEFAULT_RATE, parseReferralCodes, referralCodesProblem, SCOPE_LABEL, SCOPES, type ApiKeyRow, type Scope } from "@/lib/integrations";
import { createApiKey, revokeApiKey, setKeyReferralCodes } from "./actions";
import { SecretBox } from "./SecretBox";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

function CreateKeyDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const [name, setName] = useState("");
  const [scopes, setScopes] = useState<Scope[]>(["events"]);
  const [expires, setExpires] = useState("365");
  const [rate, setRate] = useState("");
  const [codes, setCodes] = useState("");
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [secret, setSecret] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) { setName(""); setScopes(["events"]); setExpires("365"); setRate(""); setCodes(""); setErrors({}); setError(null); setSecret(null); d.showModal(); }
    if (!open && d.open) d.close();
  }, [open]);

  const create = async () => {
    setPending(true);
    try {
      const r = await createApiKey(name, scopes, Number(expires), rate.trim() === "" ? null : Number(rate),
                                   scopes.includes("referrals") ? parseReferralCodes(codes) : []);
      if (r.ok) { setSecret(r.secret); toast.success("API key created"); } else { setError(r.error); setErrors(r.errors ?? {}); }
    } catch { setError("Something went wrong. Try again."); } finally { setPending(false); }
  };

  return (
    <dialog ref={ref} onClose={onClose} aria-labelledby="key-title"
      className="m-auto w-[min(520px,calc(100vw-2rem))] rounded-[var(--radius-card)] border border-border bg-surface p-0 text-fg shadow-2xl backdrop:bg-overlay backdrop:backdrop-blur-sm">
      <div className="space-y-4 p-5">
        <h2 id="key-title" className="text-[15px] font-semibold">{secret ? "Your new API key" : "New API key"}</h2>
        {secret ? (
          <>
            <SecretBox secret={secret} note="Copy it now and give it to the developer securely. Only a hash is stored; it cannot be shown again." />
            <p className="text-[12.5px] text-muted">Send it as <code className="font-mono">Authorization: Bearer &lt;key&gt;</code>. Revoke it here if it leaks.</p>
          </>
        ) : (
          <>
            <label className="block space-y-1">
              <span className="text-[13px] font-medium">Name</span>
              <input value={name} onChange={(x) => setName(x.target.value)} maxLength={80} placeholder="e.g. B2C CRM production" className={field} aria-invalid={Boolean(errors.name)} />
              {errors.name && <span className="text-xs text-danger">{errors.name}</span>}
            </label>
            <fieldset className="space-y-1.5">
              <legend className="text-[13px] font-medium">What it may do</legend>
              {SCOPES.map((s) => (
                <label key={s} className="flex items-center gap-2 text-[13px]">
                  <input type="checkbox" checked={scopes.includes(s)} className="accent-[var(--primary)]"
                    onChange={(x) => setScopes((cur) => (x.target.checked ? [...cur, s] : cur.filter((c) => c !== s)))} />
                  {SCOPE_LABEL[s]}
                </label>
              ))}
              {errors.scopes && <span className="text-xs text-danger">{errors.scopes}</span>}
            </fieldset>
            {scopes.includes("referrals") && (
              <label className="block space-y-1">
                <span className="text-[13px] font-medium">Referral codes it may read</span>
                <textarea value={codes} onChange={(x) => setCodes(x.target.value)} rows={2} maxLength={4000} placeholder="INF001, INF002 or a prefix such as INF*"
                  className={cn(field, "h-auto py-2")} aria-invalid={Boolean(errors.referral_codes)} />
                <span className="block text-[12px] text-subtle">Separate codes with commas or spaces. A prefix ending in * covers every code that starts with it. Any other code answers an empty list.</span>
                {errors.referral_codes && <span className="text-xs text-danger">{errors.referral_codes}</span>}
              </label>
            )}
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="block space-y-1">
                <span className="text-[13px] font-medium">Expires</span>
                <select value={expires} onChange={(x) => setExpires(x.target.value)} className={field}>
                  <option value="30">In 30 days</option><option value="90">In 90 days</option><option value="365">In 1 year</option><option value="730">In 2 years</option><option value="0">Never (not recommended)</option>
                </select>
              </label>
              <label className="block space-y-1">
                <span className="text-[13px] font-medium">Requests per minute</span>
                <input value={rate} onChange={(x) => setRate(x.target.value.replace(/\D/g, "").slice(0, 6))} inputMode="numeric" className={field}
                  placeholder={`default ${Math.max(...scopes.map((s) => DEFAULT_RATE[s] ?? 300), 0) || 300}`} aria-invalid={Boolean(errors.rate_per_minute)} />
                {errors.rate_per_minute && <span className="text-xs text-danger">{errors.rate_per_minute}</span>}
              </label>
            </div>
            <p className="text-[12px] text-subtle">Over the limit, calls get HTTP 429 with Retry-After. An alert fires 7 days before expiry.</p>
            {error && <p role="alert" className="text-[13px] text-danger">{error}</p>}
          </>
        )}
      </div>
      <div className="flex justify-end gap-2 border-t border-border bg-surface-2/60 px-5 py-3">
        {secret ? <Button size="sm" onClick={onClose}>Done</Button> : (
          <>
            <Button variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button>
            <Button size="sm" onClick={create} disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Create key</Button>
          </>
        )}
      </div>
    </dialog>
  );
}

/** M34d: the referral codes a referrals key may read (the whole list is replaced). */
function CodesDialog({ keyRow, onClose }: { keyRow: ApiKeyRow | null; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const [codes, setCodes] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (keyRow && !d.open) { setCodes((keyRow.referral_codes ?? []).join(", ")); setError(null); d.showModal(); }
    if (!keyRow && d.open) d.close();
  }, [keyRow]);

  const save = async () => {
    if (!keyRow) return;
    const list = parseReferralCodes(codes);
    const problem = referralCodesProblem(["referrals"], list);
    if (problem) { setError(problem); return; }
    setPending(true);
    try {
      const err = await setKeyReferralCodes(keyRow.id, list);
      if (err) setError(err); else { toast.success("Referral codes saved"); onClose(); }
    } catch { setError("Something went wrong. Try again."); } finally { setPending(false); }
  };

  return (
    <dialog ref={ref} onClose={onClose} aria-labelledby="codes-title"
      className="m-auto w-[min(520px,calc(100vw-2rem))] rounded-[var(--radius-card)] border border-border bg-surface p-0 text-fg shadow-2xl backdrop:bg-overlay backdrop:backdrop-blur-sm">
      <div className="space-y-3 p-5">
        <h2 id="codes-title" className="text-[15px] font-semibold">Referral codes for “{keyRow?.name ?? ""}”</h2>
        <textarea value={codes} onChange={(x) => setCodes(x.target.value)} rows={3} maxLength={4000} placeholder="INF001, INF002 or a prefix such as INF*"
          className={cn(field, "h-auto py-2")} aria-invalid={Boolean(error)} aria-label="Referral codes" />
        <p className="text-[12px] text-subtle">The key reads only these codes; any other code answers an empty list. A prefix ending in * covers every code that starts with it.</p>
        {error && <p role="alert" className="text-[13px] text-danger">{error}</p>}
      </div>
      <div className="flex justify-end gap-2 border-t border-border bg-surface-2/60 px-5 py-3">
        <Button variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button>
        <Button size="sm" onClick={save} disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save codes</Button>
      </div>
    </dialog>
  );
}

/** API keys for other systems: shown once at creation, revocable at any time. */
export function ApiKeys({ keys }: { keys: ApiKeyRow[] }) {
  const [creating, setCreating] = useState(false);
  const [revoke, setRevoke] = useState<ApiKeyRow | null>(null);
  const [editCodes, setEditCodes] = useState<ApiKeyRow | null>(null);
  return (
    <>
      <div className="flex justify-end border-b border-border px-5 py-2.5">
        <Button size="sm" onClick={() => setCreating(true)}><Plus className="size-3.5" /> New key</Button>
      </div>
      {keys.length === 0 ? (
        <EmptyState icon={KeyRound} title="No API keys yet">The B2C CRM needs one with the product-integrations scope to read hand-offs and send leads to partners.</EmptyState>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-left text-[12.5px]">
            <thead className="text-[11px] uppercase tracking-wider text-subtle">
              <tr className="border-b border-border">
                <th scope="col" className="px-5 py-2 font-medium">Name</th>
                <th scope="col" className="px-3 py-2 font-medium">Key</th>
                <th scope="col" className="px-3 py-2 font-medium">Scopes</th>
                <th scope="col" className="px-3 py-2 font-medium">Last used</th>
                <th scope="col" className="px-3 py-2 font-medium">Use (24 h)</th>
                <th scope="col" className="px-3 py-2 font-medium">Expires</th>
                <th scope="col" className="px-5 py-2"><span className="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {keys.map((k) => (
                <tr key={k.id} className={cn(k.revoked_at && "opacity-60")}>
                  <td className="px-5 py-2 font-medium text-fg">{k.name}<span className="block text-[11.5px] font-normal text-subtle">created {formatDateTime(k.created_at)}</span></td>
                  <td className="px-3 py-2 font-mono text-[12px] text-muted">{k.prefix}…</td>
                  <td className="px-3 py-2"><span className="flex flex-wrap gap-1">{k.scopes.map((s) => <Badge key={s}>{SCOPE_LABEL[s] ?? s}</Badge>)}</span>
                    {k.scopes.includes("referrals") && (
                      <span className="mt-1 block text-[11.5px] text-subtle" title={(k.referral_codes ?? []).join(", ")}>
                        {(k.referral_codes ?? []).length ? `Codes: ${(k.referral_codes ?? []).slice(0, 4).join(", ")}${(k.referral_codes ?? []).length > 4 ? ` +${(k.referral_codes ?? []).length - 4}` : ""}` : "No codes linked: reads nothing"}
                      </span>
                    )}
                  </td>
                  <td className="px-3 py-2 text-muted" title={formatDateTime(k.last_used_at)}>{k.last_used_at ? relativeTime(k.last_used_at) : "Never"}</td>
                  <td className="tabular px-3 py-2 text-muted" title={k.rate_per_minute ? `limit ${k.rate_per_minute} per minute` : "default limit"}>{k.requests_24h ?? 0}{k.rate_per_minute ? <span className="block text-[11px] text-subtle">max {k.rate_per_minute}/min</span> : null}</td>
                  <td className="px-3 py-2 text-muted" title={formatDateTime(k.expires_at ?? null)}>
                    {!k.expires_at ? <span className="text-subtle">Never</span>
                      : Date.parse(k.expires_at) < Date.now() ? <Badge tone="danger">Expired</Badge>
                      : Date.parse(k.expires_at) < Date.now() + 7 * 86400000 ? <Badge tone="warning">{relativeTime(k.expires_at)}</Badge>
                      : relativeTime(k.expires_at)}
                  </td>
                  <td className="px-5 py-2 text-right">
                    {k.revoked_at ? <Badge tone="danger">Revoked {formatDateTime(k.revoked_at)}</Badge>
                      : <span className="inline-flex gap-1">
                          {k.scopes.includes("referrals") && <Button size="sm" variant="ghost" onClick={() => setEditCodes(k)}>Codes</Button>}
                          <Button size="sm" variant="ghost" onClick={() => setRevoke(k)}>Revoke</Button>
                        </span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <CreateKeyDialog open={creating} onClose={() => setCreating(false)} />
      <CodesDialog keyRow={editCodes} onClose={() => setEditCodes(null)} />
      <ConfirmDialog
        open={revoke !== null}
        onClose={() => setRevoke(null)}
        title={`Revoke “${revoke?.name ?? ""}”?`}
        tone="danger"
        confirmLabel="Revoke"
        onConfirm={async () => {
          if (!revoke) return;
          const err = await revokeApiKey(revoke.id);
          if (err) return err;
          toast.success("Key revoked");
        }}
      >
        Every call made with it is refused from now on. This cannot be undone; create a new key if it is still needed.
      </ConfirmDialog>
    </>
  );
}
