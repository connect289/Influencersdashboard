"use client";
import { Pencil, Plus } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/states";
import { SwitchField } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { saveTier } from "@/lib/actions/insight";
import type { TierRow } from "@/lib/scorecards/data";
import { PAYOUT_CYCLES, type EntryRules, type TierBenefits } from "@/lib/scorecards/tiers";

const RULES = [
  "min_score",
  "min_enrollments_90d",
  "min_months_active",
  "min_compliance",
  "demote_after_months",
] as const;

/** One tier's form: name, rank, entry rules and benefits (empty fields are not used). */
function TierForm({ tier, nextRank, onDone }: { tier: TierRow | null; nextRank: number; onDone: () => void }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [name, setName] = useState(tier?.name ?? "");
  const [rank, setRank] = useState(String(tier?.rank ?? nextRank));
  const [rules, setRules] = useState<Record<string, string>>(
    Object.fromEntries(RULES.map((r) => [r, tier?.rules[r] !== undefined ? String(tier.rules[r]) : ""])),
  );
  const [uplift, setUplift] = useState(tier?.benefits.commission_uplift_pct?.toString() ?? "");
  const [early, setEarly] = useState(tier?.benefits.early_access_days?.toString() ?? "");
  const [cycle, setCycle] = useState(tier?.benefits.payout_cycle ?? "");
  const [note, setNote] = useState(tier?.benefits.note ?? "");
  const [active, setActive] = useState(tier?.active !== false);
  const num = (v: string) => (v.trim() === "" ? undefined : Number(v));
  return (
    <form
      className="flex flex-col gap-3"
      onSubmit={(e) => {
        e.preventDefault();
        const r: EntryRules = {};
        for (const k of RULES) {
          const v = num(rules[k] ?? "");
          if (v !== undefined) r[k] = v;
        }
        const b: TierBenefits = {
          ...(num(uplift) !== undefined ? { commission_uplift_pct: num(uplift) } : {}),
          ...(num(early) !== undefined ? { early_access_days: num(early) } : {}),
          ...(cycle ? { payout_cycle: cycle as TierBenefits["payout_cycle"] } : {}),
          ...(note.trim() ? { note: note.trim() } : {}),
        };
        run(() => saveTier({ id: tier?.id, name, rank: Number(rank), rules: r, benefits: b, active }), onDone);
      }}
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <Field id="tier-name" label={t("insight.tiers.name")} required>
          <Input id="tier-name" value={name} maxLength={40} required onChange={(e) => setName(e.target.value)} />
        </Field>
        <Field id="tier-rank" label={t("insight.tiers.rank")} hint={t("insight.tiers.rankHint")} required>
          <Input
            id="tier-rank"
            type="number"
            min={1}
            max={20}
            value={rank}
            required
            onChange={(e) => setRank(e.target.value)}
          />
        </Field>
      </div>
      <fieldset className="grid gap-3 sm:grid-cols-2">
        <legend className="mb-1 text-sm font-medium">{t("insight.tiers.rules")}</legend>
        {RULES.map((k) => (
          <Field key={k} id={`rule-${k}`} label={t(`insight.rules.${k}`)}>
            <Input
              id={`rule-${k}`}
              type="number"
              min={k === "demote_after_months" ? 1 : 0}
              max={k === "min_score" || k === "min_compliance" ? 100 : undefined}
              value={rules[k]}
              onChange={(e) => setRules((x) => ({ ...x, [k]: e.target.value }))}
            />
          </Field>
        ))}
      </fieldset>
      <fieldset className="grid gap-3 sm:grid-cols-2">
        <legend className="mb-1 text-sm font-medium">{t("insight.tiers.benefits")}</legend>
        <Field
          id="b-uplift"
          label={t("insight.benefits.commission_uplift_pct")}
          hint={t("insight.benefits.upliftHint")}
        >
          <Input
            id="b-uplift"
            type="number"
            min={0}
            max={100}
            step="0.01"
            value={uplift}
            onChange={(e) => setUplift(e.target.value)}
          />
        </Field>
        <Field id="b-early" label={t("insight.benefits.early_access_days")}>
          <Input id="b-early" type="number" min={0} max={60} value={early} onChange={(e) => setEarly(e.target.value)} />
        </Field>
        <Field id="b-cycle" label={t("insight.benefits.payout_cycle")}>
          <Select id="b-cycle" value={cycle} onChange={(e) => setCycle(e.target.value)}>
            <option value="">{t("insight.benefits.cycleDefault")}</option>
            {PAYOUT_CYCLES.map((c) => (
              <option key={c} value={c}>
                {t(`insight.cycles.${c}`)}
              </option>
            ))}
          </Select>
        </Field>
        <Field id="b-note" label={t("insight.benefits.note")}>
          <Input id="b-note" maxLength={300} value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
      </fieldset>
      <SwitchField id="tier-active" label={t("insight.tiers.active")} checked={active} onCheckedChange={setActive} />
      <Button type="submit" disabled={pending || name.trim().length < 2}>
        {t("common.save")}
      </Button>
    </form>
  );
}

/** Settings → Tiers (spec 15): the tiers, their entry rules and benefits, and how many creators hold each. */
export function TierEditor({ tiers }: { tiers: TierRow[] }) {
  const t = useTranslations();
  const router = useRouter();
  const [open, setOpen] = useState<string | null>(null);
  const done = () => {
    setOpen(null);
    router.refresh();
  };
  const nextRank = Math.max(0, ...tiers.map((x) => x.rank)) + 1;
  const ruleText = (x: TierRow) =>
    RULES.filter((k) => x.rules[k] !== undefined && k !== "demote_after_months")
      .map((k) => t(`insight.rulesShort.${k}`, { value: x.rules[k] ?? 0 }))
      .join(" · ") || t("insight.tiers.noRules");
  return (
    <div className="flex flex-col gap-4">
      <div className="flex justify-end">
        <Dialog open={open === "new"} onOpenChange={(o) => setOpen(o ? "new" : null)}>
          <DialogTrigger asChild>
            <Button size="sm">
              <Plus /> {t("insight.tiers.add")}
            </Button>
          </DialogTrigger>
          <DialogContent title={t("insight.tiers.add")} closeLabel={t("common.close")} className="md:max-w-2xl">
            <TierForm tier={null} nextRank={nextRank} onDone={done} />
          </DialogContent>
        </Dialog>
      </div>
      {tiers.length === 0 ? (
        <EmptyState title={t("insight.tiers.empty")} description={t("insight.tiers.emptyHint")} />
      ) : (
        [...tiers]
          .sort((a, b) => b.rank - a.rank)
          .map((x) => (
            <Card key={x.id}>
              <CardHeader
                title={
                  <span className="flex items-center gap-2">
                    {x.name}
                    <Badge>{t("insight.tiers.rankLabel", { rank: x.rank })}</Badge>
                    {x.active === false ? <Badge family="closed">{t("insight.tiers.inactive")}</Badge> : null}
                  </span>
                }
                description={t("insight.tiers.creators", { count: x.creators ?? 0 })}
                actions={
                  <Dialog open={open === x.id} onOpenChange={(o) => setOpen(o ? x.id : null)}>
                    <DialogTrigger asChild>
                      <Button size="sm" variant="ghost">
                        <Pencil /> {t("common.edit")}
                      </Button>
                    </DialogTrigger>
                    <DialogContent title={x.name} closeLabel={t("common.close")} className="md:max-w-2xl">
                      <TierForm tier={x} nextRank={nextRank} onDone={done} />
                    </DialogContent>
                  </Dialog>
                }
              />
              <dl className="grid gap-2 text-sm sm:grid-cols-2">
                <div>
                  <dt className="text-xs text-muted">{t("insight.tiers.rules")}</dt>
                  <dd>{ruleText(x)}</dd>
                </div>
                <div>
                  <dt className="text-xs text-muted">{t("insight.tiers.benefits")}</dt>
                  <dd>
                    {[
                      x.benefits.commission_uplift_pct
                        ? t("insight.benefitsShort.uplift", { pct: x.benefits.commission_uplift_pct })
                        : null,
                      x.benefits.early_access_days
                        ? t("insight.benefitsShort.early", { days: x.benefits.early_access_days })
                        : null,
                      x.benefits.payout_cycle ? t(`insight.cycles.${x.benefits.payout_cycle}`) : null,
                      x.benefits.note ?? null,
                    ]
                      .filter(Boolean)
                      .join(" · ") || t("insight.tiers.noBenefits")}
                  </dd>
                </div>
              </dl>
            </Card>
          ))
      )}
    </div>
  );
}
