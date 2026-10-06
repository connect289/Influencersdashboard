"use client";
import { useEffect, useRef, useState } from "react";
import { KeyRound, LoaderCircle, Pencil, Plus, Power, PowerOff, RefreshCw, Send, Webhook } from "lucide-react";
import { toast } from "sonner";
import { Badge, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { formatDateTime, relativeTime } from "@/lib/format";
import {
  B2C_DEFAULT_EVENTS, CONSUMER_LABEL, describeEvents, endpointHealth, PUBLISHED_EVENTS, WILDCARDS, type Consumer, type EndpointRow,
} from "@/lib/integrations";
import { rotateEndpointSecret, saveEndpoint, setEndpointActive, testEndpoint } from "./actions";
import { SecretBox } from "./SecretBox";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger disabled:bg-surface-2 disabled:text-subtle";
const WILDCARD_LABEL: Record<string, string> = { "b2c.*": "Everything for B2C (b2c.*)", "b2b.*": "Routing news for B2C (b2b.*)", "lead.*": "All lead events (lead.*)", "*": "Every published event" };

function EndpointDialog({ endpoint, hasB2c, open, onClose }: { endpoint: EndpointRow | null; hasB2c: boolean; open: boolean; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const firstConsumer: Consumer = hasB2c ? "influencer_dashboard" : "b2c_crm";
  const [name, setName] = useState("");
  const [consumer, setConsumer] = useState<Consumer>(firstConsumer);
  const [url, setUrl] = useState("");
  const [events, setEvents] = useState<string[]>([]);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) {
      setName(endpoint?.name ?? (hasB2c ? "" : "B2C CRM"));
      setConsumer(endpoint?.consumer ?? firstConsumer);
      setUrl(endpoint?.url ?? "");
      setEvents(endpoint?.events ?? (hasB2c ? [] : B2C_DEFAULT_EVENTS));
      setErrors({}); setError(null);
      d.showModal();
    }
    if (!open && d.open) d.close();
  }, [open, endpoint, hasB2c, firstConsumer]);

  const toggle = (t: string, on: boolean) => setEvents((cur) => (on ? [...cur, t] : cur.filter((c) => c !== t)));
  const covered = (t: string) => events.includes("*") || events.some((w) => w.endsWith(".*") && t.startsWith(w.slice(0, -1)));

  const save = async () => {
    setPending(true);
    try {
      const r = await saveEndpoint(endpoint?.id ?? null, { name, consumer, url, events });
      if (r.ok) { toast.success(endpoint ? "Endpoint saved" : "Endpoint added. Generate its signing secret next."); onClose(); }
      else { setError(r.error); setErrors(r.errors ?? {}); }
    } catch { setError("Something went wrong. Try again."); } finally { setPending(false); }
  };

  return (
    <dialog ref={ref} onClose={onClose} aria-labelledby="endpoint-title"
      className="m-auto w-[min(600px,calc(100vw-2rem))] rounded-[var(--radius-card)] border border-border bg-surface p-0 text-fg shadow-2xl backdrop:bg-overlay backdrop:backdrop-blur-sm">
      <div className="space-y-4 p-5">
        <h2 id="endpoint-title" className="text-[15px] font-semibold">{endpoint ? "Edit endpoint" : "New webhook endpoint"}</h2>
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block space-y-1">
            <span className="text-[13px] font-medium">Name</span>
            <input value={name} onChange={(x) => setName(x.target.value)} maxLength={80} className={field} aria-invalid={Boolean(errors.name)} />
            {errors.name && <span className="text-xs text-danger">{errors.name}</span>}
          </label>
          <label className="block space-y-1">
            <span className="text-[13px] font-medium">Product</span>
            <select value={consumer} onChange={(x) => setConsumer(x.target.value as Consumer)} disabled={Boolean(endpoint)} className={field}>
              {(Object.keys(CONSUMER_LABEL) as Consumer[]).filter((c) => c !== "b2c_crm" || !hasB2c || endpoint?.consumer === "b2c_crm")
                .map((c) => <option key={c} value={c}>{CONSUMER_LABEL[c]}</option>)}
            </select>
          </label>
        </div>
        <label className="block space-y-1">
          <span className="text-[13px] font-medium">URL</span>
          <input value={url} onChange={(x) => setUrl(x.target.value)} maxLength={500} placeholder="https://b2c.eduwit.in/api/b2b/webhooks" className={cn(field, "font-mono")} aria-invalid={Boolean(errors.url)} />
          {errors.url ? <span className="text-xs text-danger">{errors.url}</span> : <span className="block text-[11.5px] text-subtle">HTTPS only. Every request is signed; the receiver must check the signature.</span>}
        </label>
        <fieldset className="space-y-2 rounded-lg border border-border p-3">
          <legend className="px-1 text-[13px] font-medium">Events</legend>
          <div className="flex flex-wrap gap-x-4 gap-y-1.5">
            {WILDCARDS.map((w) => (
              <label key={w} className="flex items-center gap-1.5 text-[13px]">
                <input type="checkbox" checked={events.includes(w)} onChange={(x) => toggle(w, x.target.checked)} className="accent-[var(--primary)]" /> {WILDCARD_LABEL[w]}
              </label>
            ))}
          </div>
          <div className="grid gap-1.5 border-t border-border pt-2 sm:grid-cols-2">
            {PUBLISHED_EVENTS.map((e) => (
              <label key={e.type} className={cn("flex items-start gap-1.5 text-[12.5px]", covered(e.type) && "text-subtle")} title={e.type}>
                <input type="checkbox" checked={events.includes(e.type) || covered(e.type)} disabled={covered(e.type)}
                  onChange={(x) => toggle(e.type, x.target.checked)} className="mt-0.5 accent-[var(--primary)]" />
                <span>{e.label}</span>
              </label>
            ))}
          </div>
          {errors.events && <span className="text-xs text-danger">{errors.events}</span>}
        </fieldset>
        {error && <p role="alert" className="text-[13px] text-danger">{error}</p>}
      </div>
      <div className="flex justify-end gap-2 border-t border-border bg-surface-2/60 px-5 py-3">
        <Button variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button>
        <Button size="sm" onClick={save} disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save</Button>
      </div>
    </dialog>
  );
}

type Pending = { kind: "secret" | "active" | "test"; e: EndpointRow } | null;

/** Webhook endpoints of other products. Nothing is delivered until the endpoint has a secret and is switched on. */
export function Endpoints({ endpoints }: { endpoints: EndpointRow[] }) {
  const [editing, setEditing] = useState<EndpointRow | "new" | null>(null);
  const [confirm, setConfirm] = useState<Pending>(null);
  const [secret, setSecret] = useState<{ id: number; value: string } | null>(null);
  const hasB2c = endpoints.some((e) => e.consumer === "b2c_crm");

  return (
    <>
      <div className="flex justify-end border-b border-border px-5 py-2.5">
        <Button size="sm" onClick={() => setEditing("new")}><Plus className="size-3.5" /> {hasB2c ? "New endpoint" : "Connect the B2C CRM"}</Button>
      </div>
      {endpoints.length === 0 ? (
        <EmptyState icon={Webhook} title="No endpoints yet">
          Add the B2C CRM&apos;s webhook URL to send it every lead the engine hands to B2C, signed, with retries. Until then it can read the same events from GET /v1/handoffs.
        </EmptyState>
      ) : (
        <ul className="divide-y divide-border">
          {endpoints.map((e) => {
            const h = endpointHealth(e);
            return (
              <li key={e.id} className="space-y-2 px-5 py-4">
                <div className="flex flex-wrap items-start gap-x-3 gap-y-2">
                  <div className="min-w-0 flex-1">
                    <p className="flex flex-wrap items-center gap-2 text-[13.5px] font-medium text-fg">
                      {e.name} <Badge>{CONSUMER_LABEL[e.consumer]}</Badge> <Badge tone={h.tone}>{h.label}</Badge>
                    </p>
                    <p className="truncate font-mono text-[12px] text-muted" title={e.url}>{e.url}</p>
                    <p className="text-[12px] text-subtle">{describeEvents(e.events)}</p>
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    <Button size="sm" variant="ghost" onClick={() => setEditing(e)}><Pencil className="size-3.5" /> Edit</Button>
                    <Button size="sm" variant="secondary" onClick={() => setConfirm({ kind: "secret", e })}>
                      {e.has_secret ? <RefreshCw className="size-3.5" /> : <KeyRound className="size-3.5" />} {e.has_secret ? "New secret" : "Generate secret"}
                    </Button>
                    <Button size="sm" variant="secondary" disabled={!e.has_secret} onClick={() => setConfirm({ kind: "test", e })}><Send className="size-3.5" /> Send test</Button>
                    {e.active
                      ? <Button size="sm" variant="danger" onClick={() => setConfirm({ kind: "active", e })}><PowerOff className="size-3.5" /> Pause</Button>
                      : <Button size="sm" disabled={!e.has_secret} title={e.has_secret ? undefined : "Generate the signing secret first"} onClick={() => setConfirm({ kind: "active", e })}><Power className="size-3.5" /> Switch on</Button>}
                  </div>
                </div>
                {secret?.id === e.id && (
                  <SecretBox secret={secret.value} note="Copy this now and give it to the B2C developer securely. They verify our webhooks with it and sign their events to us with it. It will not be shown again." />
                )}
                <p className="flex flex-wrap gap-x-4 gap-y-1 text-[12px] text-muted">
                  <span>{e.delivered_24h} delivered in 24 h</span>
                  <span>{e.pending} waiting</span>
                  {e.dead > 0 && <span className="text-danger">{e.dead} gave up</span>}
                  <span title={formatDateTime(e.last_success_at)}>last success {e.last_success_at ? relativeTime(e.last_success_at) : "never"}</span>
                  {e.last_error && e.last_failure_at && (!e.last_success_at || e.last_failure_at > e.last_success_at) && (
                    <span className="max-w-full truncate text-warning" title={e.last_error}>last error: {e.last_error}</span>
                  )}
                </p>
              </li>
            );
          })}
        </ul>
      )}
      <EndpointDialog endpoint={editing === "new" ? null : editing} hasB2c={hasB2c} open={editing !== null} onClose={() => setEditing(null)} />
      <ConfirmDialog
        open={confirm?.kind === "secret"}
        onClose={() => setConfirm(null)}
        title={confirm?.e.has_secret ? "Replace the signing secret?" : "Generate the signing secret?"}
        tone={confirm?.e.has_secret ? "danger" : "primary"}
        confirmLabel="Generate"
        onConfirm={async () => {
          if (!confirm) return;
          const r = await rotateEndpointSecret(confirm.e.id);
          if (!r.ok) return r.error;
          setSecret({ id: confirm.e.id, value: r.secret });
        }}
      >
        {confirm?.e.has_secret
          ? "The receiver must switch to the new secret: webhooks are signed with it from now on, and events signed with the old one are refused."
          : "It is shown once, so be ready to copy it."}
      </ConfirmDialog>
      <ConfirmDialog
        open={confirm?.kind === "active"}
        onClose={() => setConfirm(null)}
        title={confirm?.e.active ? `Pause deliveries to ${confirm.e.name}?` : `Switch on deliveries to ${confirm?.e.name ?? ""}?`}
        tone={confirm?.e.active ? "danger" : "primary"}
        confirmLabel={confirm?.e.active ? "Pause" : "Switch on"}
        reason={{ label: "Reason for the audit log", placeholder: confirm?.e.active ? "e.g. receiver down for maintenance" : "e.g. B2C CRM verified the test event" }}
        onConfirm={async (reason) => {
          if (!confirm) return;
          const err = await setEndpointActive(confirm.e.id, !confirm.e.active, reason);
          if (err) return err;
          toast.success(confirm.e.active ? "Deliveries paused" : "Deliveries switched on");
        }}
      >
        {confirm?.e.active
          ? "New events are not queued while it is paused; deliveries already queued wait and go out when it is switched on again. Use GET /v1/handoffs to catch up."
          : "Events from now on are delivered, signed, within about 15 seconds. Earlier events are not replayed; the receiver can read them from GET /v1/handoffs."}
      </ConfirmDialog>
      <ConfirmDialog
        open={confirm?.kind === "test"}
        onClose={() => setConfirm(null)}
        title="Send a test event?"
        confirmLabel="Send"
        onConfirm={async () => {
          if (!confirm) return;
          const err = await testEndpoint(confirm.e.id);
          if (err) return err;
          toast.success("Test event queued; see Deliveries in a few seconds");
        }}
      >
        A signed <code className="font-mono">ping</code> event with <code className="font-mono">test: true</code>, sent even while the endpoint is off, so the receiver can check its signature code.
      </ConfirmDialog>
    </>
  );
}
