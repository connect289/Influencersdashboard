"use client";
import { Copy, KeyRound, Plus, Send, Trash2 } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { toast } from "sonner";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/states";
import { Switch } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { createWebhook, deleteWebhook, testWebhook, updateWebhook } from "@/lib/actions/communication";
import type { WebhookEndpoint } from "@/lib/communication/data";
import { formatDateTime } from "@/lib/format";
import { SIGNATURE_HEADER, WEBHOOK_EVENTS, type WebhookEvent } from "@/lib/webhooks/sign";

/** The signing secret, shown once after it is created or rotated. */
function SecretOnce({ secret, onClose }: { secret: string; onClose: () => void }) {
  const t = useTranslations();
  return (
    <Dialog open onOpenChange={(o) => (o ? undefined : onClose())}>
      <DialogContent title={t("communication.webhooks.secretTitle")} closeLabel={t("common.close")}>
        <p className="mb-2 text-sm">{t("communication.webhooks.secretHint", { header: SIGNATURE_HEADER })}</p>
        <div className="flex items-center gap-2">
          <code className="min-w-0 flex-1 overflow-x-auto rounded-lg bg-surface-2 px-2 py-1.5 text-xs">{secret}</code>
          <Button
            size="sm"
            variant="secondary"
            onClick={() =>
              void navigator.clipboard.writeText(secret).then(() => toast.success(t("communication.webhooks.copied")))
            }
          >
            <Copy /> {t("communication.webhooks.copy")}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function EventChecks({ value, onChange }: { value: WebhookEvent[]; onChange: (v: WebhookEvent[]) => void }) {
  const t = useTranslations();
  return (
    <fieldset>
      <legend className="mb-1 text-sm font-medium">{t("communication.webhooks.events")}</legend>
      <div className="flex flex-col gap-1 text-sm">
        {WEBHOOK_EVENTS.map((e) => (
          <label key={e} className="inline-flex items-center gap-1.5">
            <input
              type="checkbox"
              checked={value.includes(e)}
              onChange={() => onChange(value.includes(e) ? value.filter((x) => x !== e) : [...value, e])}
            />
            <span className="font-mono text-xs">{e}</span>
            <span className="text-muted">{t(`communication.webhooks.eventHelp.${e.replace(".", "_")}`)}</span>
          </label>
        ))}
      </div>
    </fieldset>
  );
}

/**
 * Outbound webhooks (spec 18): HTTPS endpoints that receive signed events (ids, handles and references only, never
 * student contact details), with the last 20 deliveries, a test event, pause, secret rotation and removal.
 */
export function WebhookManager({ endpoints, liveMode }: { endpoints: WebhookEndpoint[]; liveMode: boolean }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [url, setUrl] = useState("");
  const [description, setDescription] = useState("");
  const [events, setEvents] = useState<WebhookEvent[]>([]);
  const [secret, setSecret] = useState<string | null>(null);

  return (
    <div className="flex flex-col gap-4">
      {secret ? <SecretOnce secret={secret} onClose={() => setSecret(null)} /> : null}
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-muted">
          {liveMode ? t("communication.webhooks.liveOn") : t("communication.webhooks.liveOff")}
        </p>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button size="sm">
              <Plus /> {t("communication.webhooks.add")}
            </Button>
          </DialogTrigger>
          <DialogContent title={t("communication.webhooks.add")} closeLabel={t("common.close")}>
            <form
              className="flex flex-col gap-3"
              onSubmit={(e) => {
                e.preventDefault();
                run(
                  () => createWebhook({ url, description, events }),
                  (d) => {
                    setOpen(false);
                    setUrl("");
                    setDescription("");
                    setEvents([]);
                    if (d) setSecret(d.secret);
                  },
                );
              }}
            >
              <Field id="wh-url" label={t("communication.webhooks.url")} hint={t("communication.webhooks.urlHint")}>
                <Input
                  id="wh-url"
                  type="url"
                  required
                  pattern="https://.*"
                  maxLength={500}
                  value={url}
                  placeholder="https://"
                  onChange={(e) => setUrl(e.target.value)}
                />
              </Field>
              <Field id="wh-desc" label={t("communication.webhooks.description")}>
                <Input
                  id="wh-desc"
                  maxLength={200}
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                />
              </Field>
              <EventChecks value={events} onChange={setEvents} />
              <Button type="submit" disabled={pending || events.length === 0 || !url.startsWith("https://")}>
                {t("communication.webhooks.create")}
              </Button>
            </form>
          </DialogContent>
        </Dialog>
      </div>

      {endpoints.length === 0 ? (
        <EmptyState title={t("communication.webhooks.empty")} description={t("communication.webhooks.emptyHint")} />
      ) : (
        endpoints.map((w) => (
          <Card key={w.id}>
            <CardHeader
              title={<span className="font-mono text-sm break-all">{w.url}</span>}
              description={w.description ?? undefined}
              actions={
                <label className="inline-flex items-center gap-2 text-sm">
                  {w.active ? t("communication.webhooks.active") : t("communication.webhooks.paused")}
                  <Switch
                    checked={w.active}
                    disabled={pending}
                    aria-label={t("communication.webhooks.toggle")}
                    onCheckedChange={(v) => run(() => updateWebhook({ id: w.id, active: v }))}
                  />
                </label>
              }
            />
            <div className="mb-3 flex flex-wrap gap-1">
              {w.events.map((e) => (
                <Badge key={e}>
                  <span className="font-mono">{e}</span>
                </Badge>
              ))}
              {w.failing_since ? (
                <Badge family="problem">
                  {t("communication.webhooks.failingSince", { date: formatDateTime(w.failing_since) })}
                </Badge>
              ) : null}
            </div>
            <div className="mb-3 flex flex-wrap gap-2">
              <Button
                size="sm"
                variant="secondary"
                disabled={pending || !w.active}
                onClick={() => run(() => testWebhook(w.id))}
              >
                <Send /> {t("communication.webhooks.test")}
              </Button>
              <ConfirmDialog
                trigger={
                  <Button size="sm" variant="ghost" disabled={pending}>
                    <KeyRound /> {t("communication.webhooks.rotate")}
                  </Button>
                }
                title={t("communication.webhooks.rotateTitle")}
                description={t("communication.webhooks.rotateHint")}
                actionLabel={t("communication.webhooks.rotate")}
                onConfirm={(_, close) =>
                  run(
                    () => updateWebhook({ id: w.id, rotateSecret: true }),
                    (d) => {
                      close();
                      if (d?.secret) setSecret(d.secret);
                    },
                  )
                }
              />
              <ConfirmDialog
                trigger={
                  <Button size="sm" variant="ghost" disabled={pending}>
                    <Trash2 /> {t("communication.webhooks.delete")}
                  </Button>
                }
                title={t("communication.webhooks.deleteTitle")}
                description={t("communication.webhooks.deleteHint")}
                actionLabel={t("communication.webhooks.delete")}
                onConfirm={(_, close) => run(() => deleteWebhook(w.id), close)}
              />
            </div>
            <details>
              <summary className="cursor-pointer text-sm font-medium">
                {t("communication.webhooks.deliveries", { count: w.deliveries.length })}
              </summary>
              {w.deliveries.length === 0 ? (
                <p className="mt-2 text-sm text-muted">{t("communication.webhooks.noDeliveries")}</p>
              ) : (
                <ul className="mt-2 flex flex-col divide-y divide-line text-sm">
                  {w.deliveries.map((d) => (
                    <li key={d.id} className="flex flex-wrap items-center gap-2 py-2">
                      <span className="font-mono text-xs">{d.event}</span>
                      <StatusBadge status={d.status} label={t(`communication.webhooks.statuses.${d.status}`)} />
                      <span className="text-xs text-muted">
                        {formatDateTime(d.created_at)} · {t("communication.webhooks.attempts", { count: d.attempts })}
                        {d.last_status ? ` · HTTP ${d.last_status}` : ""}
                        {d.status === "queued" && d.attempts > 0 && d.next_attempt_at
                          ? ` · ${t("communication.webhooks.nextAttempt", { date: formatDateTime(d.next_attempt_at) })}`
                          : ""}
                      </span>
                      {d.last_error ? <span className="w-full text-xs text-danger">{d.last_error}</span> : null}
                    </li>
                  ))}
                </ul>
              )}
            </details>
          </Card>
        ))
      )}
    </div>
  );
}
