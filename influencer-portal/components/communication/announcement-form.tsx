"use client";
import { CalendarClock, Save, Send, Users } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Field } from "@/components/ui/field";
import { Input, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { announcementAudience, saveAnnouncement } from "@/lib/actions/communication";
import type { AnnouncementAdminRow } from "@/lib/communication/data";
import { PLATFORMS } from "@/lib/creators/schemas";
import { formatNumber } from "@/lib/format";
import { isEveryone, type Segment } from "@/lib/notify/segments";

type Option = { id: string; name: string };

function istLocal(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(new Date(iso).getTime() + 330 * 60_000);
  return d.toISOString().slice(0, 16);
}

/**
 * Write an announcement (spec 14): to all active creators or a segment (tier, campaign, platform, language), in the
 * portal and optionally by email or WhatsApp; save a draft, schedule it (IST) or send it now.
 */
export function AnnouncementForm({
  initial,
  tiers,
  campaigns,
}: {
  initial: AnnouncementAdminRow | null;
  tiers: Option[];
  campaigns: Option[];
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [title, setTitle] = useState(initial?.title ?? "");
  const [body, setBody] = useState(initial?.body ?? "");
  const [link, setLink] = useState(initial?.link ?? "");
  const [segment, setSegment] = useState<Segment>(
    initial?.segment ?? { tiers: [], campaigns: [], platforms: [], languages: [] },
  );
  const [languages, setLanguages] = useState(segment.languages.join(", "));
  const [channels, setChannels] = useState<("email" | "whatsapp")[]>(initial?.channels ?? []);
  const [at, setAt] = useState(istLocal(initial?.scheduled_at ?? null));
  const [count, setCount] = useState<number | null>(null);

  useEffect(() => {
    let alive = true;
    const id = window.setTimeout(() => {
      void announcementAudience(segment).then((r) => {
        if (alive) setCount(r.ok && r.data ? r.data.count : null);
      });
    }, 300);
    return () => {
      alive = false;
      window.clearTimeout(id);
    };
  }, [segment]);

  const toggle = (key: "tiers" | "campaigns" | "platforms", value: string) =>
    setSegment((s) => ({
      ...s,
      [key]: s[key].includes(value) ? s[key].filter((x) => x !== value) : [...s[key], value],
    }));

  const submit = (action: "draft" | "schedule" | "send", close?: () => void) =>
    run(
      () =>
        saveAnnouncement({
          id: initial?.id,
          title,
          body,
          link,
          segment,
          channels,
          action,
          scheduledAt: action === "schedule" ? at : undefined,
        }),
      () => {
        close?.();
        router.push("/admin/communication/announcements");
      },
    );

  const valid = title.trim().length >= 3 && body.trim().length >= 3;
  const audience =
    count === null
      ? t("communication.announcements.counting")
      : t("communication.announcements.audience", { count, shown: formatNumber(count) });

  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault();
        // Dialogs inside the form (send confirmation) submit their own forms; React bubbles those here too.
        if (e.target !== e.currentTarget) return;
        submit("draft");
      }}
    >
      <Card>
        <CardHeader title={t("communication.announcements.message")} />
        <div className="flex flex-col gap-3">
          <Field id="an-title" label={t("communication.announcements.title")}>
            <Input id="an-title" value={title} maxLength={120} required onChange={(e) => setTitle(e.target.value)} />
          </Field>
          <Field id="an-body" label={t("communication.announcements.body")}>
            <Textarea
              id="an-body"
              value={body}
              rows={5}
              maxLength={2000}
              required
              onChange={(e) => setBody(e.target.value)}
            />
          </Field>
          <Field
            id="an-link"
            label={t("communication.announcements.link")}
            hint={t("communication.announcements.linkHint")}
          >
            <Input
              id="an-link"
              value={link}
              placeholder="/creator/campaigns"
              pattern="/creator.*"
              onChange={(e) => setLink(e.target.value)}
            />
          </Field>
          <fieldset>
            <legend className="mb-1 text-sm font-medium">{t("communication.announcements.channels")}</legend>
            <p className="mb-2 text-xs text-muted">{t("communication.announcements.channelsHint")}</p>
            <div className="flex flex-wrap gap-4 text-sm">
              {(["email", "whatsapp"] as const).map((c) => (
                <label key={c} className="inline-flex items-center gap-1.5">
                  <input
                    type="checkbox"
                    checked={channels.includes(c)}
                    onChange={() => setChannels((cs) => (cs.includes(c) ? cs.filter((x) => x !== c) : [...cs, c]))}
                  />
                  {t(`notifications.channels.${c}`)}
                </label>
              ))}
            </div>
          </fieldset>
        </div>
      </Card>

      <Card>
        <CardHeader
          title={t("communication.announcements.audienceTitle")}
          description={t("communication.announcements.audienceHint")}
          actions={
            <span className="inline-flex items-center gap-1 text-sm font-medium" aria-live="polite">
              <Users className="size-4" aria-hidden /> {audience}
            </span>
          }
        />
        <div className="grid gap-4 md:grid-cols-2">
          {tiers.length ? (
            <fieldset>
              <legend className="mb-1 text-sm font-medium">{t("communication.announcements.tiers")}</legend>
              <div className="flex flex-col gap-1 text-sm">
                {tiers.map((x) => (
                  <label key={x.id} className="inline-flex items-center gap-1.5">
                    <input
                      type="checkbox"
                      checked={segment.tiers.includes(x.id)}
                      onChange={() => toggle("tiers", x.id)}
                    />
                    {x.name}
                  </label>
                ))}
              </div>
            </fieldset>
          ) : null}
          <fieldset>
            <legend className="mb-1 text-sm font-medium">{t("communication.announcements.platforms")}</legend>
            <div className="flex flex-wrap gap-x-4 gap-y-1 text-sm">
              {PLATFORMS.map((p) => (
                <label key={p} className="inline-flex items-center gap-1.5">
                  <input
                    type="checkbox"
                    checked={segment.platforms.includes(p)}
                    onChange={() => toggle("platforms", p)}
                  />
                  {t(`platforms.${p}`)}
                </label>
              ))}
            </div>
          </fieldset>
          {campaigns.length ? (
            <fieldset className="md:col-span-2">
              <legend className="mb-1 text-sm font-medium">{t("communication.announcements.campaigns")}</legend>
              <p className="mb-1 text-xs text-muted">{t("communication.announcements.campaignsHint")}</p>
              <div className="grid max-h-48 gap-1 overflow-y-auto text-sm sm:grid-cols-2">
                {campaigns.map((x) => (
                  <label key={x.id} className="inline-flex items-center gap-1.5">
                    <input
                      type="checkbox"
                      checked={segment.campaigns.includes(x.id)}
                      onChange={() => toggle("campaigns", x.id)}
                    />
                    <span className="truncate">{x.name}</span>
                  </label>
                ))}
              </div>
            </fieldset>
          ) : null}
          <Field
            id="an-langs"
            label={t("communication.announcements.languages")}
            hint={t("communication.announcements.languagesHint")}
          >
            <Input
              id="an-langs"
              value={languages}
              onChange={(e) => {
                setLanguages(e.target.value);
                const list = e.target.value
                  .split(",")
                  .map((x) => x.trim())
                  .filter((x) => x.length >= 2)
                  .slice(0, 30);
                setSegment((s) => ({ ...s, languages: list }));
              }}
            />
          </Field>
        </div>
        {isEveryone(segment) ? (
          <p className="mt-3 text-sm text-muted">{t("communication.announcements.everyone")}</p>
        ) : null}
      </Card>

      <Card>
        <CardHeader title={t("communication.announcements.when")} />
        <div className="flex flex-wrap items-end gap-2">
          <Button type="submit" size="sm" variant="secondary" disabled={pending || !valid}>
            <Save /> {t("communication.announcements.saveDraft")}
          </Button>
          <Field id="an-at" label={t("communication.announcements.scheduleAt")}>
            <Input id="an-at" type="datetime-local" value={at} onChange={(e) => setAt(e.target.value)} />
          </Field>
          <Button
            type="button"
            size="sm"
            variant="secondary"
            disabled={pending || !valid || !at}
            onClick={() => submit("schedule")}
          >
            <CalendarClock /> {t("communication.announcements.schedule")}
          </Button>
          <ConfirmDialog
            trigger={
              <Button type="button" size="sm" disabled={pending || !valid || count === 0}>
                <Send /> {t("communication.announcements.sendNow")}
              </Button>
            }
            danger={false}
            title={t("communication.announcements.sendTitle")}
            description={audience}
            actionLabel={t("communication.announcements.sendNow")}
            onConfirm={(_, close) => submit("send", close)}
          />
        </div>
      </Card>
    </form>
  );
}
