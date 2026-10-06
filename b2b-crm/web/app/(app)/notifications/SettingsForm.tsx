"use client";
import { useEffect, useState } from "react";
import { LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import { useFormAction } from "@/components/ui/useFormAction";
import type { NotificationsOverview } from "@/lib/notifications";
import { saveNotificationSettings, type FormState } from "./actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

function Row({ label, hint, error, children }: { label: string; hint: string; error?: string; children: React.ReactNode }) {
  return (
    <div className="grid gap-x-6 gap-y-1 py-3 sm:grid-cols-[minmax(0,1fr)_280px] sm:items-center">
      <div>
        <p className="text-[13px] font-medium text-fg">{label}</p>
        <p className="text-[12px] text-muted">{hint}</p>
      </div>
      <div>{children}{error && <p className="mt-1 text-xs text-danger">{error}</p>}</div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="pt-3">
      <p className="text-[11px] font-medium uppercase tracking-wider text-subtle">{title}</p>
      <div className="divide-y divide-border">{children}</div>
    </div>
  );
}

/** Quiet hours, support contact and the two providers. Secrets go to Vault and are never shown again; leave them empty to keep them. */
export function SettingsForm({ s, version }: { s: NotificationsOverview["settings"]; version: number }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveNotificationSettings, undefined);
  const [provider, setProvider] = useState(s.email.provider ?? "resend");
  const e = state?.errors ?? {};
  useEffect(() => { if (state?.ok) toast.success("Notification settings saved"); }, [state?.ok]);

  return (
    <form onSubmit={onSubmit} noValidate className="px-5 pb-2">
      <Section title="When and who to contact">
        <Row label="Quiet hours (India time)" hint="Messages are sent only between these times; others wait for the next morning." error={e.quiet_start ?? e.quiet_end}>
          <div className="flex items-center gap-2">
            <input name="quiet_start" defaultValue={s.quiet_start ?? "08:00"} className={field} aria-label="Start" aria-invalid={Boolean(e.quiet_start)} />
            <span className="text-muted">to</span>
            <input name="quiet_end" defaultValue={s.quiet_end ?? "21:00"} className={field} aria-label="End" aria-invalid={Boolean(e.quiet_end)} />
          </div>
        </Row>
        <Row label="Eduwit support contact" hint="A staffed phone number or email, shown in every message." error={e.support_contact}>
          <input name="support_contact" defaultValue={s.support_contact ?? ""} placeholder="+91 98xxx xxxxx" className={field} aria-invalid={Boolean(e.support_contact)} />
        </Row>
        <Row label="Unsubscribe link" hint="Optional. Without it, emails offer a reply-to-unsubscribe address." error={e.unsubscribe_url}>
          <input name="unsubscribe_url" defaultValue={s.unsubscribe_url ?? ""} placeholder="https://eduwit.in/unsubscribe" className={field} aria-invalid={Boolean(e.unsubscribe_url)} />
        </Row>
      </Section>

      <Section title="WhatsApp (Meta Cloud API)">
        <Row label="Phone number ID" hint="From Meta's WhatsApp Manager → API setup, for Eduwit's business number." error={e.wa_phone_number_id}>
          <input name="wa_phone_number_id" inputMode="numeric" defaultValue={s.whatsapp.phone_number_id ?? ""} className={cn(field, "font-mono")} aria-invalid={Boolean(e.wa_phone_number_id)} />
        </Row>
        <Row label="Graph API version" hint="Leave as is unless Meta retires it." error={e.wa_api_version}>
          <input name="wa_api_version" defaultValue={s.whatsapp.api_version ?? "v21.0"} className={cn(field, "font-mono")} aria-invalid={Boolean(e.wa_api_version)} />
        </Row>
        <Row label={`Access token${s.whatsapp.has_token ? " (stored)" : ""}`} hint="A permanent system-user token. Stored encrypted in Vault; leave empty to keep it." error={e.wa_token}>
          <input name="wa_token" type="password" autoComplete="off" spellCheck={false} placeholder={s.whatsapp.has_token ? "••••••••••••" : ""} className={cn(field, "font-mono")} />
        </Row>
      </Section>

      <Section title="Email">
        <Row label="Provider" hint="Sent through the provider's HTTP API." error={e.email_provider}>
          <select name="email_provider" value={provider} onChange={(x) => setProvider(x.target.value as "resend" | "brevo")} className={field}>
            <option value="resend">Resend</option>
            <option value="brevo">Brevo</option>
          </select>
        </Row>
        <Row label="Sender address" hint="On a domain verified with the provider." error={e.email_from}>
          <input name="email_from" type="email" defaultValue={s.email.from_email ?? ""} placeholder="hello@eduwit.in" className={field} aria-invalid={Boolean(e.email_from)} />
        </Row>
        <Row label="Sender name" hint="What students see in their inbox." error={e.email_from_name}>
          <input name="email_from_name" defaultValue={s.email.from_name ?? "Team Eduwit"} className={field} />
        </Row>
        <Row label="Reply-to address" hint="Optional. Where student replies go." error={e.email_reply_to}>
          <input name="email_reply_to" type="email" defaultValue={s.email.reply_to ?? ""} placeholder="support@eduwit.in" className={field} aria-invalid={Boolean(e.email_reply_to)} />
        </Row>
        <Row label={`${provider === "brevo" ? "Brevo" : "Resend"} API key${s.email.has_key ? " (stored)" : ""}`} hint="Stored encrypted in Vault; leave empty to keep it." error={e.email_api_key}>
          <input name="email_api_key" type="password" autoComplete="off" spellCheck={false} placeholder={s.email.has_key ? "••••••••••••" : ""} className={cn(field, "font-mono")} />
        </Row>
      </Section>

      <div className="divide-y divide-border border-t border-border">
        <Row label="Reason for this change" hint={`Saved as version ${version + 1} of the notification settings, with your reason.`} error={e.reason}>
          <input name="reason" maxLength={300} placeholder="e.g. WhatsApp number verified" className={field} aria-invalid={Boolean(e.reason)} />
        </Row>
      </div>
      <div className="flex items-center justify-end gap-3 border-t border-border py-3">
        {state?.error && <span role="alert" className="mr-auto text-[13px] text-danger">{state.error}</span>}
        <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save settings</Button>
      </div>
    </form>
  );
}
