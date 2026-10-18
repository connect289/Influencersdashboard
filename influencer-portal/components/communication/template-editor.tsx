"use client";
import { RotateCcw, Save, Send } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Field } from "@/components/ui/field";
import { Input, Textarea } from "@/components/ui/input";
import { Banner } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { resetTemplate, saveTemplate, sendTemplateTest } from "@/lib/actions/communication";
import type { TemplateEvent } from "@/lib/communication/data";
import { SAMPLE_VARS } from "@/lib/communication/schemas";
import { formatDateTime } from "@/lib/format";
import { COMMON_VARS } from "@/lib/notify/catalogue";
import { renderText, unknownVars, whatsappParams } from "@/lib/notify/render";
import { cn } from "@/lib/utils";

type Channel = "email" | "whatsapp";

/**
 * One event's templates (spec 14): email subject and body, or the approved WhatsApp template's name and its body
 * variables (one per line). Variables are checked as you type and in the database; the preview uses sample values.
 * Each save is a new version; "Use built-in" goes back to the notification's own text.
 */
export function TemplateEditor({ ev, liveMode }: { ev: TemplateEvent; liveMode: boolean }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [channel, setChannel] = useState<Channel>("email");
  const active = (c: Channel) => ev.templates.find((x) => x.channel === c && x.active);
  const [drafts, setDrafts] = useState(
    () =>
      Object.fromEntries(
        (["email", "whatsapp"] as const).map((c) => [
          c,
          { subject: active(c)?.subject ?? "", body: active(c)?.body ?? "", wa: active(c)?.wa_template_name ?? "" },
        ]),
      ) as Record<Channel, { subject: string; body: string; wa: string }>,
  );
  const d = drafts[channel];
  const set = (patch: Partial<typeof d>) => setDrafts((x) => ({ ...x, [channel]: { ...x[channel], ...patch } }));
  const vars = [...COMMON_VARS, ...ev.vars];
  const unknown = unknownVars(ev.event, d.subject, d.body);
  const current = active(channel);
  const history = ev.templates.filter((x) => x.channel === channel);

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader
          title={t(`notifications.events.${ev.event.replace(/\./g, "_")}` as "notifications.events.announcement")}
          description={
            <span className="font-mono text-xs">
              {ev.event}
              {ev.mandatory ? ` · ${t("notifications.prefs.required")}` : ""}
            </span>
          }
        />
        <div className="mb-3 flex gap-1" role="tablist" aria-label={t("communication.templates.channel")}>
          {(["email", "whatsapp"] as const).map((c) => (
            <button
              key={c}
              type="button"
              role="tab"
              aria-selected={channel === c}
              onClick={() => setChannel(c)}
              className={cn(
                "rounded-lg px-3 py-1.5 text-sm",
                channel === c ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
              )}
            >
              {t(`notifications.channels.${c}`)}
              {active(c) ? ` · v${active(c)?.version ?? ""}` : ""}
            </button>
          ))}
        </div>
        <p className="mb-3 text-sm text-muted">
          {current
            ? t("communication.templates.usingVersion", { version: current.version })
            : t("communication.templates.usingBuiltIn")}
        </p>
        <form
          className="flex flex-col gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            // The reset confirmation's own form submits through the React tree too.
            if (e.target !== e.currentTarget) return;
            run(() =>
              saveTemplate({ event: ev.event, channel, subject: d.subject, body: d.body, waTemplateName: d.wa }),
            );
          }}
        >
          {channel === "email" ? (
            <Field id="tpl-subject" label={t("communication.templates.subject")}>
              <Input
                id="tpl-subject"
                value={d.subject}
                maxLength={200}
                required
                onChange={(e) => set({ subject: e.target.value })}
              />
            </Field>
          ) : (
            <Field
              id="tpl-wa"
              label={t("communication.templates.waName")}
              hint={t("communication.templates.waNameHint")}
            >
              <Input
                id="tpl-wa"
                value={d.wa}
                maxLength={512}
                pattern="[a-z0-9_]+"
                required
                onChange={(e) => set({ wa: e.target.value })}
              />
            </Field>
          )}
          <Field
            id="tpl-body"
            label={channel === "email" ? t("communication.templates.body") : t("communication.templates.waBody")}
            hint={channel === "whatsapp" ? t("communication.templates.waBodyHint") : undefined}
          >
            <Textarea
              id="tpl-body"
              value={d.body}
              rows={channel === "email" ? 8 : 4}
              maxLength={5000}
              required
              onChange={(e) => set({ body: e.target.value })}
            />
          </Field>
          <div>
            <p className="mb-1 text-xs text-muted">{t("communication.templates.variables")}</p>
            <div className="flex flex-wrap gap-1">
              {vars.map((v) => (
                <button
                  key={v}
                  type="button"
                  className="rounded-md bg-surface-2 px-2 py-0.5 font-mono text-xs hover:bg-primary-soft"
                  onClick={() => set({ body: `${d.body}${d.body && !/\s$/.test(d.body) ? " " : ""}{{${v}}}` })}
                >
                  {`{{${v}}}`}
                </button>
              ))}
            </div>
          </div>
          {unknown.length ? (
            <Banner tone="danger">{t("communication.templates.unknown", { vars: unknown.join(", ") })}</Banner>
          ) : null}
          <div className="flex flex-wrap gap-2">
            <Button type="submit" size="sm" disabled={pending || unknown.length > 0 || !d.body.trim()}>
              <Save /> {t("communication.templates.save")}
            </Button>
            {channel === "email" ? (
              <Button
                type="button"
                size="sm"
                variant="secondary"
                disabled={pending || !liveMode || unknown.length > 0 || !d.body.trim() || !d.subject.trim()}
                title={liveMode ? undefined : t("communication.templates.liveOff")}
                onClick={() => run(() => sendTemplateTest({ event: ev.event, subject: d.subject, body: d.body }))}
              >
                <Send /> {t("communication.templates.test")}
              </Button>
            ) : null}
            {current ? (
              <ConfirmDialog
                trigger={
                  <Button type="button" size="sm" variant="ghost">
                    <RotateCcw /> {t("communication.templates.reset")}
                  </Button>
                }
                title={t("communication.templates.resetTitle")}
                description={t("communication.templates.resetHint")}
                actionLabel={t("communication.templates.reset")}
                onConfirm={(_, close) => run(() => resetTemplate({ event: ev.event, channel }), close)}
              />
            ) : null}
          </div>
          {!liveMode && channel === "email" ? (
            <p className="text-xs text-muted">{t("communication.templates.liveOff")}</p>
          ) : null}
        </form>
      </Card>

      <Card>
        <CardHeader
          title={t("communication.templates.preview")}
          description={t("communication.templates.previewHint")}
        />
        {channel === "email" ? (
          <div className="rounded-xl bg-surface-2 p-4 text-sm">
            <p className="font-semibold">{renderText(d.subject || ev.event, SAMPLE_VARS).text}</p>
            <p className="mt-2 whitespace-pre-line">{renderText(d.body, SAMPLE_VARS).text}</p>
          </div>
        ) : (
          <ol className="list-decimal rounded-xl bg-surface-2 p-4 pl-8 text-sm">
            {whatsappParams(d.body, SAMPLE_VARS).map((p, i) => (
              <li key={i}>{p}</li>
            ))}
          </ol>
        )}
      </Card>

      {history.length ? (
        <Card>
          <CardHeader title={t("communication.templates.history")} />
          <ul className="flex flex-col divide-y divide-line">
            {history.map((h) => (
              <li key={h.id} className="flex flex-wrap items-center gap-2 py-2 text-sm">
                <span className="font-medium">v{h.version}</span>
                {h.active ? <Badge family="success">{t("communication.templates.active")}</Badge> : null}
                <span className="text-muted">
                  {formatDateTime(h.updated_at)}
                  {h.updated_by ? ` · ${h.updated_by}` : ""}
                </span>
                <Button
                  type="button"
                  size="sm"
                  variant="ghost"
                  className="ml-auto"
                  onClick={() => set({ subject: h.subject ?? "", body: h.body, wa: h.wa_template_name ?? "" })}
                >
                  {t("communication.templates.load")}
                </Button>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
    </div>
  );
}
