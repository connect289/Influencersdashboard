"use client";
import { useEffect, useState } from "react";
import { Check, Copy, KeyRound, LoaderCircle, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { useFormAction } from "@/components/ui/useFormAction";
import { formatDateTime, relativeTime } from "@/lib/format";
import { AUTH_LABEL, AUTH_TYPES, DISPUTE_KIND_HINT, disputeDecisionCopy, disputeKindLabel, disputeProofOk, isDisputeKind, type Dispute } from "@/lib/push";
import { resolveDispute, rotateInboundSecret, savePartnerCredentials, type SaveState } from "../actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

/** The partner's API credential. The token goes to Vault and is never shown again; leave it empty to keep it. */
export function CredentialsForm({ id, authType, header, hasToken }: { id: number; authType: string | null; header: string | null; hasToken: boolean }) {
  const [state, onSubmit, pending] = useFormAction<SaveState>(savePartnerCredentials.bind(null, id), undefined);
  const [type, setType] = useState(authType ?? "bearer");
  const e = state?.errors ?? {};
  useEffect(() => { if (state?.saved) toast.success("Credentials saved"); }, [state?.saved]);
  return (
    <form onSubmit={onSubmit} noValidate className="space-y-3 px-5 py-4">
      <label className="block space-y-1"><span className="text-[12px] text-muted">How the partner&apos;s API authenticates Eduwit</span>
        <select name="type" value={type} onChange={(x) => setType(x.target.value)} className={field}>
          {AUTH_TYPES.map((t) => <option key={t} value={t}>{AUTH_LABEL[t]}</option>)}
        </select>
      </label>
      {type === "header" && (
        <label className="block space-y-1"><span className="text-[12px] text-muted">Header name</span>
          <input name="header" defaultValue={header ?? ""} placeholder="x-api-key" className={field} aria-invalid={Boolean(e.header)} />
          {e.header && <span className="text-xs text-danger">{e.header}</span>}
        </label>
      )}
      {type !== "none" && (
        <label className="block space-y-1">
          <span className="text-[12px] text-muted">{type === "basic" ? "user:password" : "Token or API key"}{hasToken && " (stored; leave empty to keep it)"}</span>
          <input name="token" type="password" autoComplete="off" spellCheck={false} placeholder={hasToken ? "••••••••••••" : ""} className={cn(field, "font-mono")} aria-invalid={Boolean(e.token)} />
          {e.token && <span className="text-xs text-danger">{e.token}</span>}
        </label>
      )}
      <div className="flex items-center justify-between gap-3">
        <p className="text-[12px] text-subtle">Stored encrypted in Supabase Vault. Nobody, including you, can read it back.</p>
        <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save</Button>
      </div>
      {state?.error && <p role="alert" className="text-[13px] text-danger">{state.error}</p>}
    </form>
  );
}

/** The secret partners sign their events with (HMAC-SHA256). Shown once, right after it is generated. */
export function SigningSecret({ id, has }: { id: number; has: boolean }) {
  const [open, setOpen] = useState(false);
  const [secret, setSecret] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  return (
    <div className="space-y-2 px-5 py-4">
      {secret ? (
        <div className="space-y-2 rounded-lg border border-warning/25 bg-warning-bg px-3 py-2">
          <p className="text-[12.5px] font-medium text-warning">Copy this now and send it to the partner securely. It will not be shown again.</p>
          <div className="flex items-center gap-2">
            <code className="min-w-0 flex-1 truncate rounded bg-surface px-2 py-1 font-mono text-[12px] text-fg">{secret}</code>
            <Button size="sm" variant="secondary" onClick={async () => { await navigator.clipboard.writeText(secret); setCopied(true); }}>
              {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />} {copied ? "Copied" : "Copy"}
            </Button>
          </div>
        </div>
      ) : (
        <p className="text-[13px] text-muted">{has ? "A signing secret is set. Generating a new one stops the old one at once." : "No signing secret yet. The partner needs one to send events, and Eduwit signs its pushes with it."}</p>
      )}
      <Button size="sm" variant={has ? "secondary" : "primary"} onClick={() => setOpen(true)}>
        {has ? <RefreshCw className="size-3.5" /> : <KeyRound className="size-3.5" />} {has ? "Generate a new secret" : "Generate the secret"}
      </Button>
      <ConfirmDialog
        open={open}
        onClose={() => setOpen(false)}
        title={has ? "Replace the signing secret?" : "Generate the signing secret?"}
        confirmLabel="Generate"
        tone={has ? "danger" : "primary"}
        onConfirm={async () => {
          const r = await rotateInboundSecret(id);
          if (!r.ok) return r.error;
          setSecret(r.secret);
          setCopied(false);
        }}
      >
        {has ? "Events signed with the old secret are refused from now on, so agree the switch with the partner first." : "It is shown once, so be ready to copy it."}
      </ConfirmDialog>
    </div>
  );
}

/** The partner's proof for one dispute row: record id and created date for a duplicate claim; the event for late activity. */
function DisputeProof({ d }: { d: Dispute }) {
  if (d.kind === "late_activity_after_lost") {
    return (
      <p className="text-[12px] text-muted">
        {d.partner_name} reported {d.partner_event_id ? <>activity (partner event <span className="font-mono">#{d.partner_event_id}</span>)</> : "an enrolment"} after the lead moved to B2C
        {" "}· claimed <span title={formatDateTime(d.created_at)}>{relativeTime(d.created_at)}</span>
      </p>
    );
  }
  const ok = disputeProofOk(d);
  return (
    <p className="flex flex-wrap items-center gap-x-1.5 gap-y-1 text-[12px] text-muted">
      <span>
        {d.partner_name} says it already had this student
        {d.existing_record_id && <> as <span className="font-mono text-fg">{d.existing_record_id}</span></>}
        {d.existing_created_on ? <>, created <span className="text-fg" title={formatDateTime(d.existing_created_on)}>{formatDateTime(d.existing_created_on)}</span></>
          : d.existing_created_at ? <>, created <span className="text-fg">{d.existing_created_at}</span></> : null}
        {" "}· claimed <span title={formatDateTime(d.created_at)}>{relativeTime(d.created_at)}</span>
      </span>
      {ok ? <Badge tone="success">With proof</Badge> : <Badge tone="warning">No proof</Badge>}
    </p>
  );
}

/**
 * Open commission disputes (m31i): a duplicate claimed within 24 hours of acceptance (PART 5.8) or partner activity after a lost
 * lead's grace ended (PART 6.1). The lead never moves; the Admin decides the commission. Upholding a duplicate claim means no
 * commission on the lead; upholding late activity lets the later enrolment earn.
 */
export function DisputeList({ disputes }: { disputes: Dispute[] }) {
  const [open, setOpen] = useState<{ d: Dispute; uphold: boolean } | null>(null);
  const copy = open ? disputeDecisionCopy(open.d.kind, open.uphold) : null;
  return (
    <>
      <ul className="divide-y divide-border">
        {disputes.map((d) => (
          <li key={d.id} className="flex flex-wrap items-center gap-x-3 gap-y-2 px-5 py-3 text-[13px]">
            <div className="min-w-0 flex-1 space-y-1">
              <p className="flex flex-wrap items-center gap-x-2 gap-y-1 font-medium text-fg">
                <span>{d.lead_name || `Lead #${d.lead_id}`}</span>
                <span className="font-mono text-[12px] text-subtle">{d.reference}</span>
                <span title={isDisputeKind(d.kind) ? DISPUTE_KIND_HINT[d.kind] : undefined}>
                  <Badge tone={d.kind === "late_activity_after_lost" ? "info" : "warning"} className="font-normal">{disputeKindLabel(d.kind)}</Badge>
                </span>
                {d.also > 0 && <span title="Later claims by the partner joined this dispute"><Badge>+{d.also} more {d.also === 1 ? "claim" : "claims"}</Badge></span>}
              </p>
              <DisputeProof d={d} />
            </div>
            <Button size="sm" variant="secondary" onClick={() => setOpen({ d, uphold: true })}>Uphold</Button>
            <Button size="sm" variant="ghost" onClick={() => setOpen({ d, uphold: false })}>Reject</Button>
          </li>
        ))}
      </ul>
      <ConfirmDialog
        open={open !== null}
        onClose={() => setOpen(null)}
        title={copy?.title ?? ""}
        confirmLabel={open?.uphold ? "Uphold" : "Reject"}
        reason={{ label: "Note for the audit log", placeholder: copy?.placeholder }}
        onConfirm={async (note) => {
          if (!open || !copy) return;
          const err = await resolveDispute(open.d.id, open.uphold, note);
          if (err) return err;
          toast.success(copy.toast);
        }}
      >
        {copy?.body}
      </ConfirmDialog>
    </>
  );
}
