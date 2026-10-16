"use client";
import { CalendarClock, Check } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input, Select, Textarea } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { logOutreach, markFollowUpDone } from "@/lib/actions/creators";
import { istToIso, OUTREACH_CHANNELS, OUTREACH_OUTCOMES } from "@/lib/creators/crm";
import { formatDate, formatDateTime } from "@/lib/format";

export interface OutreachRow {
  id: string;
  channel: string;
  direction: string;
  outcome: string;
  notes: string | null;
  next_follow_up_at: string | null;
  follow_up_done_at: string | null;
  created_at: string;
  author: string | null;
}

type Channel = (typeof OUTREACH_CHANNELS)[number];
type Outcome = (typeof OUTREACH_OUTCOMES)[number];

/** Log a call, DM or note with an optional follow-up, and see the timeline. */
export function OutreachPanel({
  creatorId,
  rows,
  canWrite,
}: {
  creatorId: string;
  rows: OutreachRow[];
  canWrite: boolean;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [v, setV] = useState({
    channel: "call" as Channel,
    direction: "outbound" as "outbound" | "inbound",
    outcome: "follow_up" as Outcome,
    notes: "",
    date: "",
    time: "10:00",
  });
  return (
    <div className="flex flex-col gap-4">
      {canWrite ? (
        <Card>
          <CardHeader title={t("creators.outreach.log")} />
          <form
            className="grid gap-3 md:grid-cols-3"
            onSubmit={(e) => {
              e.preventDefault();
              run(
                () =>
                  logOutreach({
                    creatorId,
                    channel: v.channel,
                    direction: v.direction,
                    outcome: v.outcome,
                    notes: v.notes,
                    nextFollowUp: v.date ? istToIso(v.date, v.time) : "",
                  }),
                () => setV((x) => ({ ...x, notes: "", date: "" })),
              );
            }}
          >
            <Field id="o-channel" label={t("creators.outreach.channel")}>
              <Select
                id="o-channel"
                value={v.channel}
                onChange={(e) => setV({ ...v, channel: e.target.value as Channel })}
              >
                {OUTREACH_CHANNELS.map((c) => (
                  <option key={c} value={c}>
                    {t(`creators.outreach.channels.${c}`)}
                  </option>
                ))}
              </Select>
            </Field>
            <Field id="o-dir" label={t("creators.outreach.direction")}>
              <Select
                id="o-dir"
                value={v.direction}
                onChange={(e) => setV({ ...v, direction: e.target.value as "outbound" | "inbound" })}
              >
                <option value="outbound">{t("creators.outreach.outbound")}</option>
                <option value="inbound">{t("creators.outreach.inbound")}</option>
              </Select>
            </Field>
            <Field id="o-outcome" label={t("creators.outreach.outcome")}>
              <Select
                id="o-outcome"
                value={v.outcome}
                onChange={(e) => setV({ ...v, outcome: e.target.value as Outcome })}
              >
                {OUTREACH_OUTCOMES.map((c) => (
                  <option key={c} value={c}>
                    {t(`creators.outreach.outcomes.${c}`)}
                  </option>
                ))}
              </Select>
            </Field>
            <Field id="o-notes" label={t("creators.outreach.notes")} className="md:col-span-3">
              <Textarea
                id="o-notes"
                value={v.notes}
                onChange={(e) => setV({ ...v, notes: e.target.value })}
                maxLength={4000}
              />
            </Field>
            <Field id="o-date" label={t("creators.outreach.followUpDate")} hint={t("creators.outreach.followUpHint")}>
              <Input id="o-date" type="date" value={v.date} onChange={(e) => setV({ ...v, date: e.target.value })} />
            </Field>
            <Field id="o-time" label={t("creators.outreach.followUpTime")}>
              <Input
                id="o-time"
                type="time"
                value={v.time}
                onChange={(e) => setV({ ...v, time: e.target.value })}
                disabled={!v.date}
              />
            </Field>
            <div className="flex items-end">
              <Button type="submit" disabled={pending} block>
                {t("creators.outreach.save")}
              </Button>
            </div>
          </form>
        </Card>
      ) : null}
      <Card>
        <CardHeader title={t("creators.outreach.timeline")} />
        {rows.length === 0 ? (
          <EmptyState title={t("creators.outreach.empty")} />
        ) : (
          <ol className="flex flex-col gap-4 border-l border-line pl-4">
            {rows.map((r) => (
              <li key={r.id} className="relative">
                <span className="absolute top-1.5 -left-[21px] size-2.5 rounded-full bg-primary" aria-hidden />
                <p className="flex flex-wrap items-center gap-2 text-sm">
                  <span className="font-medium">{t(`creators.outreach.channels.${r.channel as Channel}`)}</span>
                  <Badge>{t(`creators.outreach.outcomes.${r.outcome as Outcome}`)}</Badge>
                  <span className="text-xs text-muted">
                    {formatDateTime(r.created_at)}
                    {r.author ? ` · ${r.author}` : ""}
                  </span>
                </p>
                {r.notes ? <p className="mt-1 text-sm whitespace-pre-line">{r.notes}</p> : null}
                {r.next_follow_up_at ? (
                  <p className="mt-1 flex items-center gap-2 text-xs">
                    <CalendarClock className="size-3.5" aria-hidden />
                    {r.follow_up_done_at
                      ? t("creators.outreach.followUpClosed", { date: formatDate(r.next_follow_up_at) })
                      : t("creators.outreach.followUpOn", { date: formatDateTime(r.next_follow_up_at) })}
                    {!r.follow_up_done_at && canWrite ? (
                      <Button
                        size="sm"
                        variant="ghost"
                        disabled={pending}
                        onClick={() => run(() => markFollowUpDone(r.id))}
                      >
                        <Check /> {t("creators.outreach.markDone")}
                      </Button>
                    ) : null}
                  </p>
                ) : null}
              </li>
            ))}
          </ol>
        )}
      </Card>
    </div>
  );
}
