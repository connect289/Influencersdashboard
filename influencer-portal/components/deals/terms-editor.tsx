"use client";
// Builder + validation summary + save, with the live simulator alongside (spec 6.2 "deal builder UI with a live
// earnings simulator"). Saves a deal's working copy, or a preset.
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { applyCommissionUplift } from "@/lib/scorecards/uplift";
import { savePreset, updateDeal } from "@/lib/actions/deals";
import type { EngineContext } from "@/lib/compensation/engine";
import { compConfig, type CompConfig } from "@/lib/compensation/schema";
import type { TdsSection } from "@/lib/compensation/tax";
import { builderIssues, type BuilderIssue } from "@/lib/deals/builder";
import { CompBuilder } from "./comp-builder";
import { StaffSimulator } from "./simulator";

export interface SimulatorProps {
  startsOn: string;
  context: EngineContext;
  gstRateBps: number;
  sections: TdsSection[];
  estimatePaise: number | null;
  taxConfirmed: boolean;
}

export type EditorTarget =
  { kind: "deal"; dealId: string } | { kind: "preset"; id: string; name: string; description: string };

function IssueList({ issues }: { issues: BuilderIssue[] }) {
  const t = useTranslations();
  if (!issues.length) return null;
  return (
    <div role="alert" className="rounded-xl bg-danger-soft px-3 py-2 text-sm text-danger">
      <p className="font-medium">{t("deals.validation.title")}</p>
      <ul className="list-disc pl-5">
        {issues.slice(0, 12).map((i, n) => (
          <li key={n}>
            {i.code
              ? t(`deals.validation.${i.code}`, { detail: i.detail ?? "" })
              : t("deals.validation.field", {
                  where: [
                    i.section === "general" ? "" : t(`deals.sections.${i.section}`),
                    ...i.path
                      .slice(1)
                      .map((p) => (typeof p === "number" ? `#${String(p + 1)}` : String(p).replace(/_/g, " "))),
                  ]
                    .filter(Boolean)
                    .join(" › "),
                })}
          </li>
        ))}
      </ul>
    </div>
  );
}

function SavePresetDialog({ config }: { config: CompConfig }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button type="button" variant="secondary">
          {t("deals.presets.saveAs")}
        </Button>
      </DialogTrigger>
      <DialogContent
        title={t("deals.presets.saveAs")}
        description={t("deals.presets.saveAsHint")}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => savePreset({ name, description, config }),
              () => setOpen(false),
            );
          }}
        >
          <Field id="preset-name" label={t("deals.presets.name")} required>
            <Input id="preset-name" value={name} onChange={(e) => setName(e.target.value)} maxLength={80} />
          </Field>
          <Field id="preset-desc" label={t("deals.presets.description")}>
            <Textarea
              id="preset-desc"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              maxLength={500}
            />
          </Field>
          <div className="flex justify-end">
            <Button type="submit" disabled={pending || name.trim().length < 2}>
              {t("common.save")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function TermsEditor({
  initial,
  target,
  simulator,
  uplift = null,
}: {
  initial: CompConfig;
  target: EditorTarget;
  simulator: SimulatorProps;
  /** The creator's tier commission uplift, offered for new deals (staff apply it, then save). */
  uplift?: { tier: string; pct: number } | null;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [config, setConfig] = useState<CompConfig>(initial);
  const [name, setName] = useState(target.kind === "preset" ? target.name : "");
  const [description, setDescription] = useState(target.kind === "preset" ? target.description : "");
  const issues = useMemo(() => builderIssues(config), [config]);
  const valid = useMemo(() => (issues.length ? null : compConfig.parse(config)), [issues, config]);
  const invalidSections = useMemo(() => new Set(issues.map((i) => i.section)), [issues]);
  const dirty = JSON.stringify(config) !== JSON.stringify(initial);
  const [upliftApplied, setUpliftApplied] = useState(false);

  const save = () => {
    if (!valid) return;
    if (target.kind === "deal")
      run(
        () => updateDeal({ dealId: target.dealId, config: valid }),
        () => router.refresh(),
      );
    else
      run(
        () => savePreset({ id: target.id, name, description, config: valid }),
        (data) => {
          if (data && !target.id) router.push(`/admin/deals/presets/${data.id}`);
          else router.refresh();
        },
      );
  };

  return (
    <div className="grid items-start gap-4 xl:grid-cols-[minmax(0,1fr)_380px]">
      <div className="flex flex-col gap-4">
        {target.kind === "preset" ? (
          <Card>
            <div className="grid gap-3 sm:grid-cols-2">
              <Field id="p-name" label={t("deals.presets.name")} required>
                <Input id="p-name" value={name} onChange={(e) => setName(e.target.value)} maxLength={80} />
              </Field>
              <Field id="p-desc" label={t("deals.presets.description")}>
                <Input
                  id="p-desc"
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  maxLength={500}
                />
              </Field>
            </div>
          </Card>
        ) : null}
        {uplift && config.commission.length > 0 ? (
          <Card className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-sm">{t("insight.uplift.offer", { tier: uplift.tier, pct: uplift.pct })}</p>
            <Button
              type="button"
              size="sm"
              variant="secondary"
              disabled={upliftApplied}
              onClick={() => {
                setConfig((c) => applyCommissionUplift(c, uplift.pct));
                setUpliftApplied(true);
              }}
            >
              {upliftApplied ? t("insight.uplift.applied") : t("insight.uplift.apply", { pct: uplift.pct })}
            </Button>
          </Card>
        ) : null}
        <IssueList issues={issues} />
        <CompBuilder value={config} onChange={setConfig} invalidSections={invalidSections} />
        <div className="sticky bottom-20 z-10 flex flex-wrap items-center justify-end gap-2 rounded-xl bg-surface/95 p-2 ring-1 ring-line backdrop-blur md:bottom-4">
          {dirty ? <span className="mr-auto text-xs text-muted">{t("deals.builder.unsaved")}</span> : null}
          {target.kind === "deal" && valid ? <SavePresetDialog config={valid} /> : null}
          <Button
            type="button"
            onClick={save}
            disabled={
              pending ||
              !valid ||
              (!dirty && target.kind === "deal") ||
              (target.kind === "preset" && name.trim().length < 2)
            }
          >
            {target.kind === "deal" ? t("deals.builder.saveTerms") : t("deals.presets.save")}
          </Button>
        </div>
      </div>
      <div className="xl:sticky xl:top-20">
        <StaffSimulator config={valid} {...simulator} />
      </div>
    </div>
  );
}
