// Builds a deal's first compensation config from an accepted campaign offer (spec 13: "on acceptance the system
// auto-generates the deal from the preset and negotiated terms"). Pure. The base is the campaign's default preset, or
// the system preset for the offer's deal type; the negotiated fixed fee and commission choice are applied on top.
import type { OfferTerms } from "@/lib/campaigns/schemas";
import { SYSTEM_PRESETS, type PresetKey } from "@/lib/compensation/presets";
import { compConfig, type CompConfig, type FixedComponent } from "@/lib/compensation/schema";

const PRESET_FOR: Record<OfferTerms["deal_type"], PresetKey | null> = {
  fixed: "fixed_only",
  commission: "commission_only",
  hybrid: "fixed_plus_commission",
  barter: null,
};

const presetFixed = SYSTEM_PRESETS.fixed_plus_commission.config.fixed;
const presetCommission = SYSTEM_PRESETS.fixed_plus_commission.config.commission;

/** The fixed component with the negotiated fee: same id, label and percentage milestones, paid as one lump sum. */
function withFee(base: FixedComponent | undefined, fee: number): FixedComponent {
  const template =
    base && base.basis !== "retainer" && base.milestones.every((m) => m.share.type === "pct")
      ? base
      : presetFixed[0];
  if (!template) throw new Error("fixed preset missing");
  return {
    ...template,
    amount_paise: fee,
    basis: "lump_sum",
    units: 1,
    unit_label: undefined,
    retainer: undefined,
  };
}

export function configFromTerms(preset: CompConfig | null, terms: OfferTerms): CompConfig {
  const key = PRESET_FOR[terms.deal_type];
  const base: CompConfig =
    preset ?? (key ? SYSTEM_PRESETS[key].config : compConfig.parse({ schema_version: 1 }));
  const wantsFixed = terms.deal_type === "fixed" || terms.deal_type === "hybrid";
  const wantsCommission =
    terms.deal_type === "commission" ||
    terms.deal_type === "hybrid" ||
    terms.includes_commission === true;
  const fee = terms.fixed_fee_paise ?? 0;

  const fixed =
    wantsFixed && fee > 0
      ? [withFee(base.fixed[0], fee), ...base.fixed.slice(1)]
      : wantsFixed
        ? base.fixed
        : [];
  const commission = wantsCommission
    ? base.commission.length
      ? base.commission
      : presetCommission
    : [];
  const commissionIds = new Set(commission.map((r) => r.id));
  const config = {
    ...base,
    fixed,
    commission,
    floors: base.floors.filter(
      (f) => commission.length > 0 && f.rules.every((r) => commissionIds.has(r)),
    ),
    recoupment: fixed.length && commission.length ? base.recoupment : { mode: "none" as const },
  };
  return compConfig.parse(config);
}
