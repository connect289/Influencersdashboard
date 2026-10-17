"use client";
import { Search, X } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input, Select, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { saveCampaign, searchProgrammes, type ProgrammeHit } from "@/lib/actions/campaigns";
import {
  OBJECTIVES,
  VISIBILITIES,
  type DeliverableItem,
  type Eligibility,
} from "@/lib/campaigns/schemas";
import { PLATFORMS, type Platform } from "@/lib/creators/schemas";
import { formatRupees } from "@/lib/format";
import { cn } from "@/lib/utils";
import { DeliverablesEditor } from "./deliverables-editor";

export interface CampaignFormValues {
  id?: string;
  name: string;
  objective: (typeof OBJECTIVES)[number];
  description: string;
  visibility: (typeof VISIBILITIES)[number];
  startsOn: string;
  endsOn: string;
  applyBy: string;
  budgetRupees: string;
  slots: string;
  eligibility: Eligibility;
  deliverables: DeliverableItem[];
  compensationSummary: string;
  internalNotes: string;
  ownerId: string;
  presetId: string;
  contractTemplateId: string;
  briefTemplateId: string;
  programmes: ProgrammeHit[];
}

export const EMPTY_CAMPAIGN: CampaignFormValues = {
  name: "",
  objective: "leads",
  description: "",
  visibility: "open",
  startsOn: "",
  endsOn: "",
  applyBy: "",
  budgetRupees: "",
  slots: "",
  eligibility: {},
  deliverables: [{ platform: "instagram", format: "reel", count: 1 }],
  compensationSummary: "",
  internalNotes: "",
  ownerId: "",
  presetId: "",
  contractTemplateId: "",
  briefTemplateId: "",
  programmes: [],
};

const words = (v: string) =>
  v
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);

function ProgrammePicker({
  value,
  onChange,
}: {
  value: ProgrammeHit[];
  onChange: (v: ProgrammeHit[]) => void;
}) {
  const t = useTranslations();
  const [q, setQ] = useState("");
  const [hits, setHits] = useState<ProgrammeHit[]>([]);
  const active = q.trim().length >= 2;
  useEffect(() => {
    if (!active) return;
    let live = true;
    const id = setTimeout(() => {
      void searchProgrammes(q).then((r) => {
        if (live) setHits(r);
      });
    }, 250);
    return () => {
      live = false;
      clearTimeout(id);
    };
  }, [q, active]);
  const chosen = new Set(value.map((p) => p.id));
  return (
    <div className="flex flex-col gap-2">
      {value.length ? (
        <ul className="flex flex-wrap gap-1.5">
          {value.map((p) => (
            <li key={p.id}>
              <Badge family="progress" className="gap-1 py-1">
                {p.program_name} · {p.university}
                <button
                  type="button"
                  aria-label={t("campaigns.fields.removeProgramme", { name: p.program_name })}
                  onClick={() => onChange(value.filter((x) => x.id !== p.id))}
                >
                  <X className="size-3" />
                </button>
              </Badge>
            </li>
          ))}
        </ul>
      ) : null}
      <div className="relative">
        <Search
          className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-faint"
          aria-hidden
        />
        <Input
          aria-label={t("campaigns.fields.searchProgrammes")}
          placeholder={t("campaigns.fields.searchProgrammes")}
          value={q}
          onChange={(e) => setQ(e.target.value)}
          className="pl-9"
          maxLength={80}
        />
      </div>
      {active && hits.length ? (
        <ul
          className="max-h-60 overflow-y-auto rounded-xl ring-1 ring-line ring-inset"
          role="listbox"
          aria-label={t("campaigns.fields.programmes")}
        >
          {hits.map((h) => (
            <li key={h.id}>
              <button
                type="button"
                role="option"
                aria-selected={chosen.has(h.id)}
                disabled={chosen.has(h.id) || value.length >= 30}
                onClick={() => {
                  onChange([...value, h]);
                  setQ("");
                }}
                className={cn(
                  "w-full px-3 py-2 text-left text-sm hover:bg-surface-2 disabled:opacity-50",
                )}
              >
                <span className="font-medium">{h.program_name}</span>
                {h.specialization ? ` (${h.specialization})` : ""}
                <span className="block text-xs text-muted">
                  {h.university}
                  {h.mode ? ` · ${h.mode}` : ""}
                  {h.fee_total ? ` · ${formatRupees(h.fee_total, { whole: true })}` : ""}
                </span>
              </button>
            </li>
          ))}
        </ul>
      ) : active ? (
        <p className="text-xs text-muted">{t("campaigns.fields.noProgrammes")}</p>
      ) : null}
    </div>
  );
}

/** The campaign builder (spec 13): details, eligibility, deliverables, programmes, preset and templates. */
export function CampaignForm({
  initial,
  owners,
  presets,
  templates,
  briefTemplates,
}: {
  initial: CampaignFormValues;
  owners: { id: string; name: string }[];
  /** Deal presets the campaign can offer by default (accepted applications start from it). */
  presets: { id: string; name: string }[];
  /** Contract templates; empty = the default template. */
  templates: { id: string; name: string }[];
  /** Brief templates; empty = the default brief template. */
  briefTemplates: { id: string; name: string }[];
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [v, setV] = useState<CampaignFormValues>(initial);
  const set = <K extends keyof CampaignFormValues>(k: K, value: CampaignFormValues[K]) =>
    setV((x) => ({ ...x, [k]: value }));
  const setRule = (patch: Partial<Eligibility>) =>
    setV((x) => ({ ...x, eligibility: { ...x.eligibility, ...patch } }));
  const togglePlatform = (p: Platform) => {
    const cur = v.eligibility.platforms ?? [];
    setRule({ platforms: cur.includes(p) ? cur.filter((x) => x !== p) : [...cur, p] });
  };
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault();
        run(
          () =>
            saveCampaign({
              id: v.id,
              name: v.name,
              objective: v.objective,
              description: v.description,
              visibility: v.visibility,
              startsOn: v.startsOn,
              endsOn: v.endsOn,
              applyBy: v.applyBy,
              budgetRupees: v.budgetRupees === "" ? null : Number(v.budgetRupees),
              slots: v.slots === "" ? null : Number(v.slots),
              eligibility: Object.fromEntries(
                Object.entries(v.eligibility).filter(
                  ([, x]) => !(Array.isArray(x) && x.length === 0),
                ),
              ),
              deliverables: v.deliverables,
              compensationSummary: v.compensationSummary,
              internalNotes: v.internalNotes,
              ownerId: v.ownerId,
              presetId: v.presetId,
              contractTemplateId: v.contractTemplateId,
              briefTemplateId: v.briefTemplateId,
              programmeIds: v.programmes.map((p) => p.id),
            }),
          (data) => {
            if (data) router.push(`/admin/campaigns/${data.id}`);
          },
        );
      }}
    >
      <Card>
        <CardHeader title={t("campaigns.form.basics")} />
        <div className="grid gap-4 md:grid-cols-2">
          <Field id="cf-name" label={t("campaigns.fields.name")} required className="md:col-span-2">
            <Input
              id="cf-name"
              value={v.name}
              onChange={(e) => set("name", e.target.value)}
              required
              minLength={3}
              maxLength={120}
            />
          </Field>
          <Field id="cf-objective" label={t("campaigns.fields.objective")}>
            <Select
              id="cf-objective"
              value={v.objective}
              onChange={(e) => set("objective", e.target.value as CampaignFormValues["objective"])}
            >
              {OBJECTIVES.map((o) => (
                <option key={o} value={o}>
                  {t(`campaigns.objectives.${o}`)}
                </option>
              ))}
            </Select>
          </Field>
          <Field
            id="cf-visibility"
            label={t("campaigns.fields.visibility")}
            hint={t(`campaigns.visibilityHints.${v.visibility}`)}
          >
            <Select
              id="cf-visibility"
              value={v.visibility}
              onChange={(e) =>
                set("visibility", e.target.value as CampaignFormValues["visibility"])
              }
            >
              {VISIBILITIES.map((o) => (
                <option key={o} value={o}>
                  {t(`campaigns.visibilities.${o}`)}
                </option>
              ))}
            </Select>
          </Field>
          <Field
            id="cf-desc"
            label={t("campaigns.fields.description")}
            hint={t("campaigns.fields.descriptionHint")}
            className="md:col-span-2"
          >
            <Textarea
              id="cf-desc"
              value={v.description}
              onChange={(e) => set("description", e.target.value)}
              maxLength={8000}
              rows={5}
            />
          </Field>
          <Field id="cf-owner" label={t("creators.fields.owner")}>
            <Select
              id="cf-owner"
              value={v.ownerId}
              onChange={(e) => set("ownerId", e.target.value)}
            >
              <option value="">{t("creators.fields.ownerMe")}</option>
              {owners.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.name}
                </option>
              ))}
            </Select>
          </Field>
        </div>
      </Card>
      <Card>
        <CardHeader
          title={t("campaigns.fields.programmes")}
          description={t("campaigns.fields.programmesHint")}
        />
        <ProgrammePicker value={v.programmes} onChange={(p) => set("programmes", p)} />
      </Card>
      <Card>
        <CardHeader title={t("campaigns.form.schedule")} />
        <div className="grid gap-4 md:grid-cols-3">
          <Field id="cf-start" label={t("campaigns.fields.startsOn")}>
            <Input
              id="cf-start"
              type="date"
              value={v.startsOn}
              onChange={(e) => set("startsOn", e.target.value)}
            />
          </Field>
          <Field id="cf-end" label={t("campaigns.fields.endsOn")}>
            <Input
              id="cf-end"
              type="date"
              value={v.endsOn}
              onChange={(e) => set("endsOn", e.target.value)}
            />
          </Field>
          <Field id="cf-apply" label={t("campaigns.fields.applyBy")}>
            <Input
              id="cf-apply"
              type="date"
              value={v.applyBy}
              onChange={(e) => set("applyBy", e.target.value)}
            />
          </Field>
          <Field
            id="cf-budget"
            label={t("campaigns.fields.budget")}
            hint={t("campaigns.fields.budgetHint")}
          >
            <Input
              id="cf-budget"
              type="number"
              inputMode="decimal"
              min={0}
              value={v.budgetRupees}
              onChange={(e) => set("budgetRupees", e.target.value)}
            />
          </Field>
          <Field
            id="cf-slots"
            label={t("campaigns.fields.slots")}
            hint={t("campaigns.fields.slotsHint")}
          >
            <Input
              id="cf-slots"
              type="number"
              min={1}
              max={10000}
              value={v.slots}
              onChange={(e) => set("slots", e.target.value)}
            />
          </Field>
        </div>
      </Card>
      <Card>
        <CardHeader
          title={t("campaigns.fields.deliverables")}
          description={t("campaigns.fields.deliverablesHint")}
        />
        <DeliverablesEditor
          value={v.deliverables}
          onChange={(d) => set("deliverables", d)}
          idPrefix="cf-d"
        />
        <Field
          id="cf-preset"
          label={t("campaigns.fields.preset")}
          hint={t("campaigns.fields.presetHint")}
          className="mt-4"
        >
          <Select
            id="cf-preset"
            value={v.presetId}
            onChange={(e) => set("presetId", e.target.value)}
          >
            <option value="">{t("campaigns.fields.presetByType")}</option>
            {presets.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field
          id="cf-template"
          label={t("campaigns.fields.contractTemplate")}
          hint={t("campaigns.fields.contractTemplateHint")}
          className="mt-4"
        >
          <Select
            id="cf-template"
            value={v.contractTemplateId}
            onChange={(e) => set("contractTemplateId", e.target.value)}
          >
            <option value="">{t("campaigns.fields.contractTemplateDefault")}</option>
            {templates.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field
          id="cf-brief-template"
          label={t("campaigns.fields.briefTemplate")}
          hint={t("campaigns.fields.briefTemplateHint")}
          className="mt-4"
        >
          <Select
            id="cf-brief-template"
            value={v.briefTemplateId}
            onChange={(e) => set("briefTemplateId", e.target.value)}
          >
            <option value="">{t("campaigns.fields.briefTemplateDefault")}</option>
            {briefTemplates.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field
          id="cf-comp"
          label={t("campaigns.fields.compensation")}
          hint={t("campaigns.fields.compensationHint")}
          className="mt-4"
        >
          <Textarea
            id="cf-comp"
            value={v.compensationSummary}
            onChange={(e) => set("compensationSummary", e.target.value)}
            maxLength={1000}
          />
        </Field>
      </Card>
      <Card>
        <CardHeader
          title={t("campaigns.form.eligibility")}
          description={t("campaigns.form.eligibilityHint")}
        />
        <div className="grid gap-4 md:grid-cols-2">
          <Field id="cf-minf" label={t("campaigns.eligibility.minFollowers")}>
            <Input
              id="cf-minf"
              type="number"
              min={0}
              inputMode="numeric"
              value={v.eligibility.min_followers ?? ""}
              onChange={(e) =>
                setRule({ min_followers: e.target.value ? Number(e.target.value) : undefined })
              }
            />
          </Field>
          <fieldset className="md:col-span-2">
            <legend className="mb-1.5 text-sm font-medium">
              {t("campaigns.eligibility.platforms")}
            </legend>
            <div className="flex flex-wrap gap-1.5">
              {PLATFORMS.map((p) => {
                const on = (v.eligibility.platforms ?? []).includes(p);
                return (
                  <button
                    type="button"
                    key={p}
                    aria-pressed={on}
                    onClick={() => togglePlatform(p)}
                    className={cn(
                      "rounded-full px-3 py-1 text-sm ring-1 ring-line-strong ring-inset",
                      on && "bg-primary text-on-primary ring-primary",
                    )}
                  >
                    {t(`platforms.${p}`)}
                  </button>
                );
              })}
            </div>
          </fieldset>
          <Field
            id="cf-niches"
            label={t("campaigns.eligibility.niches")}
            hint={t("profile.fields.listHint")}
          >
            <Input
              id="cf-niches"
              defaultValue={(v.eligibility.niches ?? []).join(", ")}
              onBlur={(e) => setRule({ niches: words(e.target.value) })}
            />
          </Field>
          <Field
            id="cf-langs"
            label={t("campaigns.eligibility.languages")}
            hint={t("profile.fields.listHint")}
          >
            <Input
              id="cf-langs"
              defaultValue={(v.eligibility.languages ?? []).join(", ")}
              onBlur={(e) => setRule({ languages: words(e.target.value) })}
            />
          </Field>
          <Field
            id="cf-states"
            label={t("campaigns.eligibility.states")}
            hint={t("profile.fields.listHint")}
          >
            <Input
              id="cf-states"
              defaultValue={(v.eligibility.states ?? []).join(", ")}
              onBlur={(e) => setRule({ states: words(e.target.value) })}
            />
          </Field>
        </div>
      </Card>
      <Card>
        <CardHeader
          title={t("campaigns.fields.internalNotes")}
          description={t("campaigns.fields.internalNotesHint")}
        />
        <Textarea
          aria-label={t("campaigns.fields.internalNotes")}
          value={v.internalNotes}
          onChange={(e) => set("internalNotes", e.target.value)}
          maxLength={4000}
        />
      </Card>
      <div className="flex justify-end gap-2">
        <Button type="submit" disabled={pending || v.name.trim().length < 3}>
          {v.id ? t("common.save") : t("campaigns.create")}
        </Button>
      </div>
    </form>
  );
}
