"use client";
import { useTranslations } from "next-intl";
import { Field } from "@/components/ui/field";
import { Input, Select, Textarea } from "@/components/ui/input";
import {
  DEAL_TYPES,
  type DealType,
  type DeliverableItem,
  type OfferTerms,
} from "@/lib/campaigns/schemas";
import { formatPaise } from "@/lib/format";
import { DeliverablesEditor } from "./deliverables-editor";

/** Read-only view of offer terms. */
export function TermsView({ terms }: { terms: Partial<OfferTerms> }) {
  const t = useTranslations();
  const items = terms.deliverables ?? [];
  return (
    <dl className="grid grid-cols-1 gap-x-6 gap-y-1.5 text-sm sm:grid-cols-2">
      <div className="flex justify-between gap-3">
        <dt className="text-muted">{t("campaigns.terms.dealType")}</dt>
        <dd className="font-medium">
          {terms.deal_type ? t(`campaigns.dealTypes.${terms.deal_type}`) : "—"}
        </dd>
      </div>
      {terms.fixed_fee_paise ? (
        <div className="flex justify-between gap-3">
          <dt className="text-muted">{t("campaigns.terms.fixedFee")}</dt>
          <dd className="font-medium tabular-nums">
            {formatPaise(terms.fixed_fee_paise, { whole: true })}
          </dd>
        </div>
      ) : null}
      {terms.includes_commission ? (
        <div className="flex justify-between gap-3 sm:col-span-2">
          <dt className="text-muted">{t("campaigns.terms.commission")}</dt>
          <dd className="font-medium">{t("campaigns.terms.commissionYes")}</dd>
        </div>
      ) : null}
      {items.length ? (
        <div className="sm:col-span-2">
          <dt className="text-muted">{t("campaigns.fields.deliverables")}</dt>
          <dd className="font-medium">
            {items
              .map(
                (d) =>
                  `${String(d.count)} × ${t(`formats.${d.format}`)} (${t(`platforms.${d.platform}`)})`,
              )
              .join(", ")}
          </dd>
        </div>
      ) : null}
      {terms.usage_rights ? (
        <div className="sm:col-span-2">
          <dt className="text-muted">{t("campaigns.terms.usageRights")}</dt>
          <dd>{terms.usage_rights}</dd>
        </div>
      ) : null}
      {terms.exclusivity_days ? (
        <div className="flex justify-between gap-3">
          <dt className="text-muted">{t("campaigns.terms.exclusivity")}</dt>
          <dd>{t("campaigns.terms.days", { count: terms.exclusivity_days })}</dd>
        </div>
      ) : null}
      {terms.notes ? (
        <div className="sm:col-span-2">
          <dt className="text-muted">{t("campaigns.terms.notes")}</dt>
          <dd className="whitespace-pre-line">{terms.notes}</dd>
        </div>
      ) : null}
    </dl>
  );
}

export interface TermsDraft {
  deal_type: DealType;
  feeRupees: string;
  includes_commission: boolean;
  deliverables: DeliverableItem[];
  usage_rights: string;
  exclusivity_days: string;
  notes: string;
}

export function draftFromTerms(
  t: Partial<OfferTerms> | undefined,
  deliverables: DeliverableItem[] = [],
): TermsDraft {
  return {
    deal_type: t?.deal_type ?? "fixed",
    feeRupees: t?.fixed_fee_paise ? String(t.fixed_fee_paise / 100) : "",
    includes_commission: t?.includes_commission ?? false,
    deliverables: t?.deliverables?.length ? t.deliverables : deliverables,
    usage_rights: t?.usage_rights ?? "",
    exclusivity_days: t?.exclusivity_days ? String(t.exclusivity_days) : "",
    notes: t?.notes ?? "",
  };
}

export function termsFromDraft(d: TermsDraft): OfferTerms {
  const fee = d.feeRupees.trim() === "" ? undefined : Math.round(Number(d.feeRupees) * 100);
  return {
    deal_type: d.deal_type,
    fixed_fee_paise: d.deal_type === "fixed" || d.deal_type === "hybrid" ? fee : undefined,
    includes_commission:
      d.deal_type === "commission" || d.deal_type === "hybrid" ? true : d.includes_commission,
    deliverables: d.deliverables,
    usage_rights: d.usage_rights.trim() || undefined,
    exclusivity_days: d.exclusivity_days ? Number(d.exclusivity_days) : undefined,
    notes: d.notes.trim() || undefined,
  };
}

/** Edit offer terms (application or counter-offer). */
export function TermsForm({
  value,
  onChange,
  idPrefix,
}: {
  value: TermsDraft;
  onChange: (v: TermsDraft) => void;
  idPrefix: string;
}) {
  const t = useTranslations();
  const set = <K extends keyof TermsDraft>(k: K, v: TermsDraft[K]) =>
    onChange({ ...value, [k]: v });
  const needsFee = value.deal_type === "fixed" || value.deal_type === "hybrid";
  return (
    <div className="flex flex-col gap-3">
      <div className="grid gap-3 md:grid-cols-2">
        <Field id={`${idPrefix}-type`} label={t("campaigns.terms.dealType")}>
          <Select
            id={`${idPrefix}-type`}
            value={value.deal_type}
            onChange={(e) => set("deal_type", e.target.value as DealType)}
          >
            {DEAL_TYPES.map((d) => (
              <option key={d} value={d}>
                {t(`campaigns.dealTypes.${d}`)}
              </option>
            ))}
          </Select>
        </Field>
        {needsFee ? (
          <Field id={`${idPrefix}-fee`} label={t("campaigns.terms.fixedFeeRupees")} required>
            <Input
              id={`${idPrefix}-fee`}
              type="number"
              inputMode="decimal"
              min={1}
              step="1"
              value={value.feeRupees}
              onChange={(e) => set("feeRupees", e.target.value)}
              required
            />
          </Field>
        ) : null}
      </div>
      <p className="text-xs text-muted">{t(`campaigns.dealTypeHints.${value.deal_type}`)}</p>
      <fieldset>
        <legend className="mb-1.5 text-sm font-medium">{t("campaigns.fields.deliverables")}</legend>
        <DeliverablesEditor
          value={value.deliverables}
          onChange={(v) => set("deliverables", v)}
          idPrefix={`${idPrefix}-d`}
        />
      </fieldset>
      <div className="grid gap-3 md:grid-cols-2">
        <Field
          id={`${idPrefix}-usage`}
          label={t("campaigns.terms.usageRights")}
          hint={t("campaigns.terms.usageHint")}
        >
          <Input
            id={`${idPrefix}-usage`}
            value={value.usage_rights}
            onChange={(e) => set("usage_rights", e.target.value)}
            maxLength={300}
          />
        </Field>
        <Field id={`${idPrefix}-excl`} label={t("campaigns.terms.exclusivityDays")}>
          <Input
            id={`${idPrefix}-excl`}
            type="number"
            min={0}
            max={365}
            value={value.exclusivity_days}
            onChange={(e) => set("exclusivity_days", e.target.value)}
          />
        </Field>
      </div>
      <Field id={`${idPrefix}-notes`} label={t("campaigns.terms.notes")}>
        <Textarea
          id={`${idPrefix}-notes`}
          value={value.notes}
          onChange={(e) => set("notes", e.target.value)}
          maxLength={1000}
        />
      </Field>
    </div>
  );
}
