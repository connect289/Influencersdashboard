"use client";
import { useState } from "react";
import Link from "next/link";
import { Check, CircleDashed, Copy, LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import type { IntakeOverview } from "@/lib/intake";
import { saveConnections } from "./actions";
import { field, label } from "./ui";

function Url({ value }: { value: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="flex items-center gap-2">
      <code className="min-w-0 flex-1 truncate rounded bg-surface-2 px-2 py-1 font-mono text-[12px] text-fg">{value}</code>
      <Button size="sm" variant="secondary" onClick={async () => { await navigator.clipboard.writeText(value); setCopied(true); setTimeout(() => setCopied(false), 1500); }}>
        {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />} {copied ? "Copied" : "Copy"}
      </Button>
    </div>
  );
}

const IsSet = ({ on }: { on: boolean }) => on ? <Badge tone="success"><Check className="size-3" /> Set</Badge> : <Badge><CircleDashed className="size-3" /> Not set</Badge>;

/** Secrets are typed in, sent once to Vault and never shown again. */
export function Connections({ c, site }: { c: IntakeOverview["connections"]; site: string }) {
  const [meta, setMeta] = useState({ verify_token: "", app_secret: "", page_token: "", api_version: c.meta.api_version });
  const [google, setGoogle] = useState({ key: "" });
  const [pending, setPending] = useState(false);
  const save = async () => {
    setPending(true);
    try {
      const e = await saveConnections({ meta, google });
      if (e) toast.error(e); else { toast.success("Saved to the vault"); setMeta({ ...meta, verify_token: "", app_secret: "", page_token: "" }); setGoogle({ key: "" }); }
    } finally { setPending(false); }
  };
  const secret = (v: string, set: (v: string) => void, id: string, l: string, on: boolean, hint: string) => (
    <label htmlFor={id} className="block space-y-1">
      <span className={cn(label, "flex items-center justify-between gap-2")}>{l} <IsSet on={on} /></span>
      <input id={id} type="password" autoComplete="off" className={field} value={v} placeholder={on ? "Leave empty to keep the current one" : ""} onChange={(e) => set(e.target.value)} />
      <span className="block text-xs text-muted">{hint}</span>
    </label>
  );
  const metaReady = c.meta.verify_token && c.meta.app_secret && c.meta.page_token;
  return (
    <div className="divide-y divide-border">
      <section className="space-y-4 p-5">
        <div className="flex items-center justify-between gap-3">
          <h3 className="text-[13.5px] font-semibold text-fg">Meta Lead Ads</h3>
          {metaReady ? <Badge tone="success">Connected</Badge> : <Badge tone="warning">Not connected</Badge>}
        </div>
        <ol className="list-decimal space-y-1 pl-5 text-[12.5px] text-muted">
          <li>In the Meta app (Webhooks → Page → <span className="font-mono">leadgen</span>), set the callback URL below and the same verify token as here.</li>
          <li>Subscribe the Facebook Page to the app, and give the app a Page access token with <span className="font-mono">leads_retrieval</span>.</li>
          <li>Each new lead arrives as an ID; Eduwit fetches it from the Graph API within seconds.</li>
        </ol>
        <Url value={`${site}/v1/webhooks/meta/leadgen`} />
        <div className="grid gap-4 md:grid-cols-2">
          {secret(meta.verify_token, (v) => setMeta({ ...meta, verify_token: v }), "m-verify", "Verify token", c.meta.verify_token, "Any long random text; type the same in Meta.")}
          {secret(meta.app_secret, (v) => setMeta({ ...meta, app_secret: v }), "m-secret", "App secret", c.meta.app_secret, "From the Meta app's basic settings; checks each webhook's signature.")}
          {secret(meta.page_token, (v) => setMeta({ ...meta, page_token: v }), "m-token", "Page access token", c.meta.page_token, "A long-lived Page token; used to fetch each lead.")}
          <label className="block space-y-1">
            <span className={label}>Graph API version</span>
            <input className={field} value={meta.api_version} maxLength={10} onChange={(e) => setMeta({ ...meta, api_version: e.target.value })} />
          </label>
        </div>
      </section>
      <section className="space-y-4 p-5">
        <div className="flex items-center justify-between gap-3">
          <h3 className="text-[13.5px] font-semibold text-fg">Google Ads lead forms</h3>
          {c.google.key ? <Badge tone="success">Connected</Badge> : <Badge tone="warning">Not connected</Badge>}
        </div>
        <p className="text-[12.5px] text-muted">In the lead form asset (Lead delivery → Webhook integration), paste the URL below and the same key as here. Use &ldquo;Send test data&rdquo; to check it: test leads are kept as test leads.</p>
        <Url value={`${site}/v1/webhooks/google/leadform`} />
        <div className="grid gap-4 md:grid-cols-2">{secret(google.key, (v) => setGoogle({ key: v }), "g-key", "Key", c.google.key, "Any long random text; Google sends it with each lead.")}</div>
      </section>
      <section className="space-y-3 p-5">
        <div className="flex items-center justify-between gap-3">
          <h3 className="text-[13.5px] font-semibold text-fg">Intake API</h3>
          <Badge tone={c.api_keys > 0 ? "success" : "neutral"}>{c.api_keys} {c.api_keys === 1 ? "key" : "keys"} with the intake scope</Badge>
        </div>
        <p className="text-[12.5px] text-muted">For the website, landing pages and other tools: <span className="font-mono">POST</span> a lead with an API key and an Idempotency-Key header. The contract is <span className="font-mono">docs/intake-api.md</span>. Create keys under <Link href="/system?tab=integrations" className="text-info hover:underline">System → Webhooks and API keys</Link>.</p>
        <Url value={`${site}/v1/leads`} />
      </section>
      <div className="flex justify-end bg-surface-2/40 px-5 py-3">
        <Button onClick={save} disabled={pending}>{pending && <LoaderCircle className="size-4 animate-spin" />} Save connections</Button>
      </div>
    </div>
  );
}
