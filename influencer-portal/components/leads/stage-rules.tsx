"use client";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import type { StageRuleRow } from "@/lib/leads/data";
import { StageRuleForm } from "./stage-rule-form";

export function StageRules({ rules, canEdit }: { rules: StageRuleRow[]; canEdit: boolean }) {
  const t = useTranslations();
  const [editing, setEditing] = useState<StageRuleRow | "new" | null>(null);
  const describe = (c: StageRuleRow["conditions"][number]) =>
    `${t(`leads.stages.fields.${c.field as "stage"}`)} ${c.in ? `∈ {${c.in.join(", ")}}` : c.present ? t("leads.stages.modes.present") : c.empty ? t("leads.stages.modes.empty") : t("leads.stages.modes.is_true")}`;
  return (
    <>
      {canEdit ? (
        <Button size="sm" className="mb-3" onClick={() => setEditing("new")}>
          {t("leads.stages.add")}
        </Button>
      ) : null}
      <ol className="flex flex-col divide-y divide-line rounded-[var(--radius-card)] bg-surface shadow-[var(--shadow-card)]">
        {rules.map((r) => (
          <li
            key={r.id}
            className={
              r.active
                ? "flex flex-wrap items-center gap-2 p-3 text-sm"
                : "flex flex-wrap items-center gap-2 p-3 text-sm opacity-60"
            }
          >
            <span className="w-10 font-mono text-xs text-muted">{r.priority}</span>
            <span className="min-w-0 flex-1">{r.conditions.map(describe).join(" · ")}</span>
            <span className="flex flex-wrap items-center gap-1">
              {r.creator_stage ? (
                <Badge family="progress">{t(`leads.stages.names.${r.creator_stage}`)}</Badge>
              ) : null}
              {r.flag ? <Badge family="attention">{t(`leads.flags.${r.flag}`)}</Badge> : null}
              {r.reason_category ? (
                <span className="text-xs text-muted">{r.reason_category}</span>
              ) : null}
            </span>
            {canEdit ? (
              <Button size="sm" variant="ghost" onClick={() => setEditing(r)}>
                {t("common.edit")}
              </Button>
            ) : null}
          </li>
        ))}
      </ol>
      {editing ? (
        <Dialog open onOpenChange={(o) => (o ? undefined : setEditing(null))}>
          <DialogContent
            title={editing === "new" ? t("leads.stages.add") : t("leads.stages.edit")}
            closeLabel={t("common.close")}
            className="md:max-w-2xl"
          >
            <StageRuleForm
              rule={editing === "new" ? null : editing}
              onDone={() => setEditing(null)}
            />
          </DialogContent>
        </Dialog>
      ) : null}
    </>
  );
}
