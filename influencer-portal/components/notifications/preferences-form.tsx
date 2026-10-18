"use client";
import { Lock } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { toast } from "sonner";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Select } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { setDigestPreference, setNotificationPreference } from "@/lib/actions/messaging";
import type { PreferencesView } from "@/lib/messaging/data";
import {
  channelLocked,
  channelOn,
  DELIVERY_CHANNELS,
  EVENT_GROUPS,
  EVENTS,
  eventsFor,
  type Audience,
  type DeliveryChannel,
  type EventKey,
  type Preference,
} from "@/lib/notify/catalogue";
import { DIGEST_FREQUENCIES, type DigestFrequency } from "@/lib/notify/digest";

export function eventLabelKey(event: string): string {
  return `notifications.events.${event.replace(/\./g, "_")}`;
}

/**
 * Notification choices (spec 14): per event and channel; in-app is always on, and events that carry an obligation
 * (contracts, payouts, KYC) cannot be turned off on their default channels. Plus the digest frequency and channel.
 */
export function PreferencesForm({
  audience,
  initial,
  digestDefault,
  whatsappAvailable,
}: {
  audience: Audience;
  initial: PreferencesView;
  /** The default digest frequency (setting notifications.delivery); null hides the digest choice (agencies). */
  digestDefault: DigestFrequency | null;
  whatsappAvailable: boolean;
}) {
  const t = useTranslations();
  const [prefs, setPrefs] = useState<Preference[]>(initial.prefs);
  const [frequency, setFrequency] = useState<DigestFrequency>(initial.digest?.frequency ?? digestDefault ?? "off");
  const [digestChannel, setDigestChannel] = useState<DeliveryChannel>(initial.digest?.channel ?? "email");
  const { pending, run } = useAction();
  const channels = DELIVERY_CHANNELS.filter((c) => c === "email" || whatsappAvailable);
  const mine = eventsFor(audience);

  async function toggle(event: EventKey, channel: DeliveryChannel, enabled: boolean) {
    const before = prefs;
    setPrefs((ps) => [...ps.filter((p) => !(p.event === event && p.channel === channel)), { event, channel, enabled }]);
    const r = await setNotificationPreference({ event, channel, enabled });
    if (!r.ok) {
      setPrefs(before);
      toast.error(r.error);
    }
  }

  return (
    <div className="flex flex-col gap-4">
      {digestDefault !== null ? (
        <Card>
          <CardHeader title={t("notifications.prefs.digest")} description={t("notifications.prefs.digestHint")} />
          <form
            className="grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end"
            onSubmit={(e) => {
              e.preventDefault();
              run(() => setDigestPreference({ frequency, channel: digestChannel }));
            }}
          >
            <Field id="digest-frequency" label={t("notifications.prefs.frequency")}>
              <Select
                id="digest-frequency"
                value={frequency}
                onChange={(e) => setFrequency(e.target.value as DigestFrequency)}
              >
                {DIGEST_FREQUENCIES.map((f) => (
                  <option key={f} value={f}>
                    {t(`notifications.prefs.frequencies.${f}`)}
                  </option>
                ))}
              </Select>
            </Field>
            <Field id="digest-channel" label={t("notifications.prefs.channel")}>
              <Select
                id="digest-channel"
                value={digestChannel}
                disabled={frequency === "off"}
                onChange={(e) => setDigestChannel(e.target.value as DeliveryChannel)}
              >
                {channels.map((c) => (
                  <option key={c} value={c}>
                    {t(`notifications.channels.${c}`)}
                  </option>
                ))}
              </Select>
            </Field>
            <button
              type="submit"
              disabled={pending}
              className="h-11 rounded-xl bg-primary px-4 text-sm font-medium text-on-primary disabled:opacity-60"
            >
              {t("common.save")}
            </button>
          </form>
        </Card>
      ) : null}
      {EVENT_GROUPS.map((g) => {
        const events = mine.filter((k) => EVENTS[k].group === g);
        if (events.length === 0) return null;
        return (
          <Card key={g}>
            <CardHeader title={t(`notifications.groups.${g}`)} />
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-muted">
                  <th className="py-1 pr-2 font-medium">{t("notifications.prefs.event")}</th>
                  <th className="w-16 py-1 text-center font-medium">{t("notifications.channels.in_app")}</th>
                  {channels.map((c) => (
                    <th key={c} className="w-16 py-1 text-center font-medium">
                      {t(`notifications.channels.${c}`)}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {events.map((k) => {
                  const def = EVENTS[k];
                  const label = t(eventLabelKey(k) as "notifications.events.announcement");
                  return (
                    <tr key={k}>
                      <th scope="row" className="py-2 pr-2 text-left font-normal">
                        {label}
                        {def.mandatory ? (
                          <span className="ml-1.5 inline-flex items-center gap-0.5 text-xs text-muted">
                            <Lock className="size-3" aria-hidden /> {t("notifications.prefs.required")}
                          </span>
                        ) : null}
                      </th>
                      <td className="py-2 text-center">
                        <Switch
                          checked
                          disabled
                          aria-label={t("notifications.prefs.switch", {
                            event: label,
                            channel: t("notifications.channels.in_app"),
                          })}
                        />
                      </td>
                      {channels.map((c) => {
                        return (
                          <td key={c} className="py-2 text-center">
                            <Switch
                              checked={channelOn(k, c, prefs)}
                              disabled={channelLocked(k, c)}
                              onCheckedChange={(v) => void toggle(k, c, v)}
                              aria-label={t("notifications.prefs.switch", {
                                event: label,
                                channel: t(`notifications.channels.${c}`),
                              })}
                            />
                          </td>
                        );
                      })}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </Card>
        );
      })}
    </div>
  );
}
