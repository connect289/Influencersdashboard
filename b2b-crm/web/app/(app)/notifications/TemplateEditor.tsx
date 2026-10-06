"use client";
import { useEffect, useRef, useState } from "react";
import { LoaderCircle, Mail, MessageCircle } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import { useFormAction } from "@/components/ui/useFormAction";
import { relativeTime } from "@/lib/format";
import { CHANNEL_LABEL, LANGUAGE_LABEL, VARIABLES, VARIABLE_LABEL, renderTemplate, unknownVariables, type Template } from "@/lib/notifications";
import { previewTemplate, saveTemplate, type FormState } from "./actions";

const box = "rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";
const field = "w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

/** Sample values until the server preview for a partner arrives. */
const SAMPLE = (lang: string): Record<string, string> => ({
  student_first_name: lang === "hi" ? "Priya" : "Ravi",
  programme_label: "Online MBA (Finance)",
  partner_display_name: "Partner name",
  expected_contact_window: "within 2 working hours",
  eduwit_support_contact: "support@eduwit.in",
});

/** One template: the text with its variables, a live preview with a real partner's name and calling hours, and Draft/Active. */
export function TemplateEditor({ t, partners }: { t: Template; partners: { id: number; name: string }[] }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveTemplate.bind(null, t.id), undefined);
  const [body, setBody] = useState(t.body);
  const [subject, setSubject] = useState(t.subject ?? "");
  const [partnerId, setPartnerId] = useState<number | null>(partners[0]?.id ?? null);
  const [vars, setVars] = useState<Record<string, string>>(SAMPLE(t.language));
  const area = useRef<HTMLTextAreaElement>(null);
  const e = state?.errors ?? {};
  const bad = unknownVariables(`${body} ${subject}`);

  useEffect(() => { if (state?.ok) toast.success(`${CHANNEL_LABEL[t.channel]} template (${LANGUAGE_LABEL[t.language]}) saved`); }, [state?.ok, t.channel, t.language]);
  useEffect(() => {
    let live = true;
    previewTemplate(t.id, partnerId).then((r) => { if (live && r.ok) setVars({ ...SAMPLE(t.language), ...r.preview.variables }); });
    return () => { live = false; };
  }, [t.id, t.language, partnerId]);

  const insert = (v: string) => {
    const el = area.current;
    const tag = `{{${v}}}`;
    if (!el) { setBody((b) => b + tag); return; }
    const [a, b] = [el.selectionStart, el.selectionEnd];
    const next = body.slice(0, a) + tag + body.slice(b);
    setBody(next);
    requestAnimationFrame(() => { el.focus(); el.setSelectionRange(a + tag.length, a + tag.length); });
  };

  const text = renderTemplate(body, vars);
  const Icon = t.channel === "whatsapp" ? MessageCircle : Mail;

  return (
    <form onSubmit={onSubmit} noValidate className="grid gap-5 px-5 py-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,0.85fr)]">
      <input type="hidden" name="channel" value={t.channel} />
      <div className="min-w-0 space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Icon className="size-4 text-muted" />
          <p className="text-[13px] font-semibold text-fg">{CHANNEL_LABEL[t.channel]} · {LANGUAGE_LABEL[t.language]}</p>
          <Badge tone={t.status === "active" ? "success" : "neutral"}>{t.status === "active" ? "Active" : "Draft"}</Badge>
          <span className="text-[12px] text-subtle">version {t.version}{t.version > 1 && <> · saved {relativeTime(t.updated_at)}</>}</span>
        </div>

        {t.channel === "email" && (
          <label className="block space-y-1"><span className="text-[12px] text-muted">Subject</span>
            <input name="subject" value={subject} onChange={(x) => setSubject(x.target.value)} maxLength={150} className={cn(field, "h-9")} aria-invalid={Boolean(e.subject)} />
            {e.subject && <span className="text-xs text-danger">{e.subject}</span>}
          </label>
        )}
        <label className="block space-y-1"><span className="text-[12px] text-muted">Message</span>
          <textarea ref={area} name="body" value={body} onChange={(x) => setBody(x.target.value)} rows={t.channel === "email" ? 10 : 6} maxLength={4000}
            className={cn(field, "py-2 leading-5")} aria-invalid={Boolean(e.body) || bad.length > 0} />
          {(e.body || bad.length > 0) && <span className="text-xs text-danger">{e.body ?? `Unknown variable: ${bad.join(", ")}`}</span>}
        </label>
        <div className="flex flex-wrap gap-1.5" aria-label="Insert a variable">
          {VARIABLES.map((v) => (
            <button key={v} type="button" onClick={() => insert(v)} title={`Insert {{${v}}}`}
              className="rounded-md border border-border bg-surface-2 px-2 py-0.5 text-[11.5px] text-muted transition-colors hover:border-border-strong hover:text-fg">
              {VARIABLE_LABEL[v]}
            </button>
          ))}
        </div>

        {t.channel === "whatsapp" && (
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block space-y-1"><span className="text-[12px] text-muted">Approved template name in Meta</span>
              <input name="wa_template" defaultValue={t.wa_template ?? ""} placeholder="eduwit_partner_assigned" className={cn(field, "h-9 font-mono")} aria-invalid={Boolean(e.wa_template)} />
              {e.wa_template && <span className="text-xs text-danger">{e.wa_template}</span>}
            </label>
            <label className="block space-y-1"><span className="text-[12px] text-muted">Template language code</span>
              <input name="wa_language" defaultValue={t.wa_language ?? t.language} placeholder="en" className={cn(field, "h-9 font-mono")} />
            </label>
            <p className="text-[12px] text-subtle sm:col-span-2">
              WhatsApp sends the text Meta approved, filling its five variables in this order: first name, programme, partner, when, support contact.
              Keep this copy identical to the approved template; editing it here does not change what Meta sends.
            </p>
          </div>
        )}

        <div className="flex flex-wrap items-center justify-end gap-3 pt-1">
          {state?.error && <span role="alert" className="mr-auto text-[13px] text-danger">{state.error}</span>}
          <select name="status" defaultValue={t.status} className={cn(box, "h-9")} aria-label="Status">
            <option value="draft">Draft (not sent)</option>
            <option value="active">Active</option>
          </select>
          <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save</Button>
        </div>
      </div>

      <div className="min-w-0 space-y-2">
        <div className="flex items-center justify-between gap-2">
          <p className="text-[12px] text-muted">Preview</p>
          <select value={partnerId ?? ""} onChange={(x) => setPartnerId(x.target.value ? Number(x.target.value) : null)} className={cn(box, "h-8 max-w-[220px] text-[12.5px]")} aria-label="Preview for partner">
            <option value="">Sample partner</option>
            {partners.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </div>
        {t.channel === "whatsapp" ? (
          <div className="rounded-xl bg-[#e5ddd5] p-3 dark:bg-[#0b141a]">
            <div className="max-w-[92%] whitespace-pre-wrap rounded-lg rounded-tl-none bg-white px-3 py-2 text-[13px] leading-5 text-[#111b21] shadow-sm dark:bg-[#202c33] dark:text-[#e9edef]">{text}</div>
          </div>
        ) : (
          <div className="overflow-hidden rounded-xl border border-border bg-surface-2">
            <div className="border-b border-border bg-surface px-3 py-2 text-[12.5px]">
              <p className="truncate font-medium text-fg">{renderTemplate(subject, vars) || "No subject"}</p>
            </div>
            <div className="space-y-3 whitespace-pre-wrap px-3 py-3 text-[13px] leading-5 text-fg">{text}</div>
            <p className="border-t border-border px-3 py-2 text-[11.5px] text-subtle">Sent with the partner&apos;s logo and colour, Eduwit&apos;s support contact and an unsubscribe link.</p>
          </div>
        )}
        <p className="text-[11.5px] text-subtle">&ldquo;When&rdquo; follows the partner&apos;s working hours and holidays at the next sending slot.</p>
      </div>
    </form>
  );
}
