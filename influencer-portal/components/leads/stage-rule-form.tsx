"use client";
// Edit one stage-mapping rule (Super Admin / settings editors). Conditions are field + values; all must match.
import { Plus, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { SwitchField } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { saveStageRule } from "@/lib/actions/links";
import { CREATOR_STAGES, STAGE_FIELDS, type CreatorStage, type StageField } from "@/lib/attribution/stages";
import type { StageRuleRow } from "@/lib/leads/data";

type Cond = { field: StageField; mode: "in" | "present" | "empty" | "is_true"; values: string };

const toCond = (c: StageRuleRow["conditions"][number]): Cond => ({
  field: (STAGE_FIELDS as readonly string[]).includes(c.field) ? (c.field as StageField) : "stage",
  mode: c.in ? "in" : c.present ? "present" : c.empty ? "empty" : "is_true",
  values: (c.in ?? []).join(", "),
});

export function StageRuleForm({ rule, onDone }: { rule: StageRuleRow | null; onDone: () => void }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [priority, setPriority] = useState(String(rule?.priority ?? 100));
  const [conds, setConds] = useState<Cond[]>(
    rule ? rule.conditions.map(toCond) : [{ field: "stage", mode: "in", values: "" }],
  );
  const [stage, setStage] = useState<CreatorStage | "">(rule?.creator_stage ?? "");
  const [reason, setReason] = useState(rule?.reason_category ?? "");
  const [flag, setFlag] = useState<"" | "cancelled" | "under_review">(rule?.flag ?? "");
  const [active, setActive] = useState(rule?.active ?? true);
  return (
    <form
      className="flex flex-col gap-3"
      onSubmit={(e) => {
        e.preventDefault();
        run(
          () =>
            saveStageRule({
              id: rule?.id ?? null,
              priority: Number(priority),
              conditions: conds.map((c) =>
                c.mode === "in"
                  ? {
                      field: c.field,
                      in: c.values
                        .split(",")
                        .map((v) => v.trim())
                        .filter(Boolean),
                    }
                  : { field: c.field, [c.mode]: true },
              ),
              creatorStage: stage || null,
              reasonCategory: reason,
              flag: flag || null,
              active,
            }),
          () => (router.refresh(), onDone()),
        );
      }}
    >
      <Field id="sr-priority" label={t("leads.stages.priority")} hint={t("leads.stages.priorityHint")}>
        <Input
          id="sr-priority"
          type="number"
          min={1}
          max={9999}
          value={priority}
          onChange={(e) => setPriority(e.target.value)}
        />
      </Field>
      <fieldset className="flex flex-col gap-2">
        <legend className="mb-1 text-sm font-medium">{t("leads.stages.conditions")}</legend>
        {conds.map((c, i) => (
          <div key={i} className="grid gap-2 sm:grid-cols-[1fr_1fr_2fr_auto]">
            <Select
              aria-label={t("leads.stages.field")}
              value={c.field}
              onChange={(e) =>
                setConds(conds.map((x, j) => (j === i ? { ...x, field: e.target.value as StageField } : x)))
              }
            >
              {STAGE_FIELDS.map((f) => (
                <option key={f} value={f}>
                  {t(`leads.stages.fields.${f}`)}
                </option>
              ))}
            </Select>
            <Select
              aria-label={t("leads.stages.mode")}
              value={c.mode}
              onChange={(e) =>
                setConds(conds.map((x, j) => (j === i ? { ...x, mode: e.target.value as Cond["mode"] } : x)))
              }
            >
              {(["in", "present", "empty", "is_true"] as const).map((m) => (
                <option key={m} value={m}>
                  {t(`leads.stages.modes.${m}`)}
                </option>
              ))}
            </Select>
            <Input
              aria-label={t("leads.stages.values")}
              disabled={c.mode !== "in"}
              placeholder={t("leads.stages.valuesHint")}
              value={c.values}
              onChange={(e) => setConds(conds.map((x, j) => (j === i ? { ...x, values: e.target.value } : x)))}
            />
            <Button
              type="button"
              variant="ghost"
              size="icon"
              aria-label={t("common.remove")}
              disabled={conds.length === 1}
              onClick={() => setConds(conds.filter((_, j) => j !== i))}
            >
              <X />
            </Button>
          </div>
        ))}
        {conds.length < 6 ? (
          <Button
            type="button"
            size="sm"
            variant="secondary"
            className="self-start"
            onClick={() => setConds([...conds, { field: "stage", mode: "in", values: "" }])}
          >
            <Plus /> {t("common.add")}
          </Button>
        ) : null}
      </fieldset>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id="sr-stage" label={t("leads.stages.creatorStage")}>
          <Select id="sr-stage" value={stage} onChange={(e) => setStage(e.target.value as CreatorStage | "")}>
            <option value="">{t("leads.stages.keepEvaluating")}</option>
            {CREATOR_STAGES.map((s) => (
              <option key={s} value={s}>
                {t(`leads.stages.names.${s}`)}
              </option>
            ))}
          </Select>
        </Field>
        <Field id="sr-reason" label={t("leads.stages.reason")}>
          <Input id="sr-reason" maxLength={80} value={reason} onChange={(e) => setReason(e.target.value)} />
        </Field>
        <Field id="sr-flag" label={t("leads.stages.flag")}>
          <Select id="sr-flag" value={flag} onChange={(e) => setFlag(e.target.value as typeof flag)}>
            <option value="">—</option>
            <option value="cancelled">{t("leads.flags.cancelled")}</option>
            <option value="under_review">{t("leads.flags.under_review")}</option>
          </Select>
        </Field>
      </div>
      <SwitchField id="sr-active" label={t("leads.stages.active")} checked={active} onCheckedChange={setActive} />
      <div className="flex justify-end gap-2">
        <Button type="button" variant="ghost" onClick={onDone}>
          {t("common.cancel")}
        </Button>
        <Button type="submit" disabled={pending || (!stage && !flag)}>
          {t("common.save")}
        </Button>
      </div>
    </form>
  );
}
