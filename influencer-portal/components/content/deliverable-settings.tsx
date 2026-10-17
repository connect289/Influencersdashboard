"use client";
// Staff settings for one deliverable: title, specs, stages (locked once work starts), due dates, revision limit,
// the rule id the deal's compensation uses, and complete / cancel.
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { SwitchField } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { setDeliverableStatus, updateDeliverable } from "@/lib/actions/content";
import type { DeliverableDetail } from "@/lib/content/data";
import { DUE_STAGES, move, STAGES, type DueStage, type StageToggles } from "@/lib/content/workflow";

/** ISO instant → the IST calendar date (YYYY-MM-DD) for a date input. */
export function istDate(iso: string): string {
  return new Date(Date.parse(iso) + 330 * 60_000).toISOString().slice(0, 10);
}
/** A date input value → the end of that IST day as an ISO instant. */
export const endOfIstDay = (ymd: string) => new Date(`${ymd}T23:59:59+05:30`).toISOString();

export function DueDatesInputs({
  idPrefix,
  value,
  onChange,
  stages,
}: {
  idPrefix: string;
  value: Partial<Record<DueStage, string>>;
  onChange: (v: Partial<Record<DueStage, string>>) => void;
  stages: StageToggles;
}) {
  const t = useTranslations();
  const shown = DUE_STAGES.filter((s) => s === "live" || stages[s as keyof StageToggles]);
  return (
    <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
      {shown.map((s) => (
        <Field key={s} id={`${idPrefix}-${s}`} label={t(`content.dueStages.${s}`)}>
          <Input
            id={`${idPrefix}-${s}`}
            type="date"
            value={value[s] ? istDate(value[s]) : ""}
            onChange={(e) => {
              const rest = Object.fromEntries(Object.entries(value).filter(([k]) => k !== s));
              onChange(e.target.value ? { ...rest, [s]: endOfIstDay(e.target.value) } : rest);
            }}
          />
        </Field>
      ))}
    </div>
  );
}

export function DeliverableSettings({ d }: { d: DeliverableDetail }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const closed = d.status === "completed" || d.status === "cancelled";
  const stagesLocked = !["not_started", "brief_acknowledged"].includes(d.status);
  const [title, setTitle] = useState(d.title);
  const [stages, setStages] = useState<StageToggles>(d.stages);
  const [due, setDue] = useState(d.due_dates);
  const [limit, setLimit] = useState(String(d.revision_limit));
  const [ref, setRef] = useState(d.config_ref ?? "");
  const [duration, setDuration] = useState(typeof d.specs.duration_s === "number" ? String(d.specs.duration_s) : "");
  const [ratio, setRatio] = useState(typeof d.specs.aspect_ratio === "string" ? d.specs.aspect_ratio : "");
  const [notes, setNotes] = useState(typeof d.specs.notes === "string" ? d.specs.notes : "");
  const canComplete = move(d.status, "complete", d.stages).ok;
  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader title={t("content.settings.title")} />
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () =>
                updateDeliverable({
                  id: d.id,
                  title,
                  stages,
                  dueDates: due,
                  revisionLimit: Number(limit) || 0,
                  configRef: ref.trim() || null,
                  specs: { duration_s: duration ? Number(duration) : null, aspect_ratio: ratio.trim() || null, notes },
                }),
              () => router.refresh(),
            );
          }}
        >
          <fieldset disabled={closed} className="flex flex-col gap-4">
            <Field id="ds-title" label={t("content.settings.name")} required>
              <Input
                id="ds-title"
                required
                minLength={2}
                maxLength={120}
                value={title}
                onChange={(e) => setTitle(e.target.value)}
              />
            </Field>
            <div className="grid gap-3 md:grid-cols-3">
              <Field id="ds-dur" label={t("content.settings.duration")}>
                <Input
                  id="ds-dur"
                  type="number"
                  min={1}
                  max={7200}
                  value={duration}
                  onChange={(e) => setDuration(e.target.value)}
                />
              </Field>
              <Field id="ds-ratio" label={t("content.settings.ratio")}>
                <Input
                  id="ds-ratio"
                  maxLength={10}
                  placeholder="9:16"
                  value={ratio}
                  onChange={(e) => setRatio(e.target.value)}
                />
              </Field>
              <Field id="ds-limit" label={t("content.settings.revisionLimit")}>
                <Input
                  id="ds-limit"
                  type="number"
                  min={0}
                  max={20}
                  value={limit}
                  onChange={(e) => setLimit(e.target.value)}
                />
              </Field>
            </div>
            <Field id="ds-notes" label={t("content.settings.notes")}>
              <Input id="ds-notes" maxLength={500} value={notes} onChange={(e) => setNotes(e.target.value)} />
            </Field>
            <div>
              <p className="mb-2 text-sm font-medium">{t("content.settings.stages")}</p>
              {stagesLocked ? <p className="mb-2 text-xs text-muted">{t("content.settings.stagesLocked")}</p> : null}
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {STAGES.map((s) => (
                  <SwitchField
                    key={s}
                    id={`ds-stage-${s}`}
                    label={t(`content.stages.${s}`)}
                    checked={stages[s]}
                    disabled={stagesLocked}
                    onCheckedChange={(on) => setStages({ ...stages, [s]: on })}
                  />
                ))}
              </div>
            </div>
            <div>
              <p className="mb-2 text-sm font-medium">{t("content.settings.due")}</p>
              <DueDatesInputs idPrefix="ds-due" value={due} onChange={setDue} stages={stages} />
            </div>
            <Field id="ds-ref" label={t("content.settings.ruleId")} hint={t("content.settings.ruleIdHint")}>
              <Input
                id="ds-ref"
                maxLength={40}
                pattern="[a-z0-9][a-z0-9_\-]{0,39}"
                value={ref}
                onChange={(e) => setRef(e.target.value.toLowerCase())}
              />
            </Field>
            <Button type="submit" className="self-start" disabled={pending}>
              {t("common.save")}
            </Button>
          </fieldset>
        </form>
      </Card>
      {!closed ? (
        <Card>
          <CardHeader title={t("content.settings.closeTitle")} description={t("content.settings.closeHint")} />
          <div className="flex flex-wrap gap-2">
            {canComplete ? (
              <Button
                type="button"
                disabled={pending}
                onClick={() =>
                  run(
                    () => setDeliverableStatus({ id: d.id, action: "complete" }),
                    () => router.refresh(),
                  )
                }
              >
                {t("content.settings.complete")}
              </Button>
            ) : null}
            <ConfirmDialog
              trigger={<Button variant="danger">{t("content.settings.cancel")}</Button>}
              title={t("content.settings.cancelTitle")}
              description={t("content.settings.cancelHint")}
              actionLabel={t("content.settings.cancel")}
              reasonLabel={t("content.checks.reason")}
              pending={pending}
              onConfirm={(reason, close) =>
                run(
                  () => setDeliverableStatus({ id: d.id, action: "cancel", reason }),
                  () => {
                    close();
                    router.refresh();
                  },
                )
              }
            />
          </div>
        </Card>
      ) : null}
    </div>
  );
}
