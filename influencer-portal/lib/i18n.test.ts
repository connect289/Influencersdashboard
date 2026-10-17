// Every translation key used in code exists in messages/en.json, and every setting field has a label.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { SETTING_KEYS, settingJsonSchema } from "@/lib/settings/registry";
import { STAFF_ROLES } from "@/lib/auth/permissions";
import { AGENCY_NAV, CREATOR_NAV, STAFF_NAV } from "@/lib/nav";
import { CONTRACT_TABS } from "@/components/contracts/contract-view";
import { CONTRACT_STATUSES } from "@/lib/contracts/data";
import { SAMPLE_KINDS } from "@/lib/contracts/sample";
import { CONTRACT_DB_ERRORS, EDITABLE_CATEGORIES, SIGN_ERRORS } from "@/lib/contracts/schemas";
import { SIGN_CHANNELS } from "@/lib/contracts/signing";
import {
  CONTACT_KINDS,
  CONTENT_FORMATS,
  GST_STATUSES,
  KYC_DB_ERRORS,
  KYC_FORM_ERRORS,
  PLATFORMS,
} from "@/lib/creators/schemas";
import { AGENCY_GRANTS } from "@/lib/agencies/schemas";
import {
  CREATOR_STATUSES,
  IMPORT_REASON_CODES,
  OUTREACH_CHANNELS,
  OUTREACH_OUTCOMES,
  PIPELINE_STAGES,
  TASK_PRIORITIES,
} from "@/lib/creators/crm";
import { WIZARD_STEPS } from "@/lib/creators/onboarding";
import {
  APPLICATION_STATUSES,
  CAMPAIGN_STATUSES,
  DEAL_TYPES,
  ELIGIBILITY_GAPS,
  OBJECTIVES,
  STATUS_MOVES,
  VISIBILITIES,
} from "@/lib/campaigns/schemas";
import {
  BASIS_TYPES,
  BONUS_METRICS,
  CONFIRMATIONS,
  FEE_KINDS,
  FIXED_BASES,
  METRICS,
  TRIGGER_TYPES,
} from "@/lib/compensation/schema";
import { BREAKDOWN_KEYS } from "@/lib/compensation/simulator";
import { ENTRY_TYPES } from "@/lib/compensation/engine";
import {
  BONUS_AMOUNTS,
  BONUS_WINDOWS,
  PENALTY_TYPES,
  RECOUP_MODES,
  SCOPE_TYPES,
  SECTIONS,
  SLAB_MODES,
  SLAB_PERIODS,
  VALIDATION_CODES,
} from "@/lib/deals/builder";
import { DEAL_DB_ERRORS, DEAL_MODELS, DEAL_STATUSES, VERSION_ORIGINS, VERSION_STATES } from "@/lib/deals/schemas";
import en from "@/messages/en.json";

const root = join(import.meta.dirname, "..");
function files(dir: string): string[] {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) return f === "node_modules" || f.startsWith(".") ? [] : files(p);
    return /\.(ts|tsx)$/.test(f) && !f.endsWith(".test.ts") ? [p] : [];
  });
}

function has(key: string): boolean {
  let node: unknown = en;
  for (const part of key.split(".")) {
    if (typeof node !== "object" || node === null || !(part in node)) return false;
    node = (node as Record<string, unknown>)[part];
  }
  return typeof node === "string";
}

describe("messages", () => {
  const sources = ["app", "components", "lib"].flatMap((d) => files(join(root, d)));
  const keys = new Set<string>();
  for (const f of sources)
    for (const m of readFileSync(f, "utf8").matchAll(/\bt\("([a-zA-Z0-9_.]+)"/g)) keys.add(m[1] ?? "");

  it("finds keys to check", () => expect(keys.size).toBeGreaterThan(100));
  it.each([...keys])("has %s", (k) => expect(has(k)).toBe(true));

  it("labels every navigation item", () => {
    for (const i of [...STAFF_NAV, ...CREATOR_NAV, ...AGENCY_NAV]) expect(has(i.labelKey), i.labelKey).toBe(true);
  });

  it("labels every value used as a dynamic key", () => {
    const keys = [
      ...Object.values(KYC_DB_ERRORS),
      ...Object.values(KYC_FORM_ERRORS),
      ...PLATFORMS.map((p) => `platforms.${p}`),
      ...CONTENT_FORMATS.map((f) => `formats.${f}`),
      ...GST_STATUSES.map((g) => `kyc.gst.${g}`),
      ...CONTACT_KINDS.map((k) => `profile.contacts.kinds.${k}`),
      ...AGENCY_GRANTS.map((g) => `agencies.grants.${g}`),
      ...PIPELINE_STAGES.map((x) => `creators.stages.${x}`),
      ...CREATOR_STATUSES.map((x) => `creators.statuses.${x}`),
      ...OUTREACH_CHANNELS.map((x) => `creators.outreach.channels.${x}`),
      ...OUTREACH_OUTCOMES.map((x) => `creators.outreach.outcomes.${x}`),
      ...TASK_PRIORITIES.map((x) => `tasks.priorities.${x}`),
      ...IMPORT_REASON_CODES.map((x) => `creators.import.reasons.${x}`),
      ...["created", "duplicate", "error"].map((x) => `creators.import.results.${x}`),
      ...["block", "unblock", "delete"].flatMap((x) =>
        ["title", "body", "action"].map((y) => `creators.confirm.${x}.${y}`),
      ),
      ...["overview", "profile", "kyc", "outreach", "tasks", "agencies", "history"].map((x) => `creators.tabs.${x}`),
      ...["tag_add", "tag_remove", "owner", "stage"].map((x) => `creators.bulk.${x}`),
      ...["open", "done", "cancelled"].map((x) => `tasks.statusDone.${x}`),
      ...WIZARD_STEPS.map((x) => `onboarding.steps.${x}`),
      ...OBJECTIVES.map((x) => `campaigns.objectives.${x}`),
      ...CAMPAIGN_STATUSES.map((x) => `campaigns.statuses.${x}`),
      ...VISIBILITIES.flatMap((x) => [`campaigns.visibilities.${x}`, `campaigns.visibilityHints.${x}`]),
      ...DEAL_TYPES.flatMap((x) => [`campaigns.dealTypes.${x}`, `campaigns.dealTypeHints.${x}`]),
      ...APPLICATION_STATUSES.map((x) => `campaigns.applicationStatuses.${x}`),
      ...ELIGIBILITY_GAPS.map((x) => `campaigns.gaps.${x}`),
      ...Object.values(STATUS_MOVES)
        .flat()
        .map((x) => `campaigns.moves.${x}`),
      ...["sent", "accepted", "declined", "countered", "withdrawn"].map((x) => `campaigns.invites.statuses.${x}`),
      ...["open", "superseded", "accepted", "rejected"].map((x) => `campaigns.offers.statuses.${x}`),
      ...["creator", "agency", "eduwit"].map((x) => `campaigns.application.sides.${x}`),
      ...["to_review", "accepted", "applications", "invites_open"].map((x) => `campaigns.stats.${x}`),
      ...["approve", "changes", "decline"].map((x) => `onboarding.review.done.${x}`),
      ...["self", "invited"].map((x) => `onboarding.queue.source.${x}`),
      ...["name", "email", "handle", "url", "followers", "consent", "generic"].map((x) => `auth.signup.errors.${x}`),
      ...["pending", "submitted", "verified", "rejected"].map((s) => `kyc.status.${s}`),
      ...DEAL_STATUSES.flatMap((x) => [`deals.statuses.${x}`, `deals.moves.${x}`, `deals.moveHints.${x}`]),
      ...DEAL_MODELS.map((x) => `deals.models.${x}`),
      ...VERSION_STATES.map((x) => `deals.versionStates.${x}`),
      ...VERSION_ORIGINS.map((x) => `deals.origins.${x}`),
      ...DEAL_DB_ERRORS.map(([, k]) => `deals.errors.${k}`),
      ...ENTRY_TYPES.map((x) => `deals.entryTypes.${x}`),
      ...TRIGGER_TYPES.map((x) => `deals.triggers.${x}`),
      ...METRICS.map((x) => `deals.metrics.${x}`),
      ...FIXED_BASES.map((x) => `deals.fixedBases.${x}`),
      ...BASIS_TYPES.flatMap((x) => [`deals.bases.${x}`, `deals.summary.bases.${x}`]),
      ...CONFIRMATIONS.map((x) => `deals.confirmations.${x}`),
      ...FEE_KINDS.map((x) => `deals.feeKinds.${x}`),
      ...BONUS_METRICS.map((x) => `deals.bonusMetrics.${x}`),
      ...BONUS_AMOUNTS.map((x) => `deals.bonusAmounts.${x}`),
      ...BONUS_WINDOWS.map((x) => `deals.windows.${x}`),
      ...PENALTY_TYPES.map((x) => `deals.penaltyTypes.${x}`),
      ...RECOUP_MODES.map((x) => `deals.recoupModes.${x}`),
      ...SCOPE_TYPES.map((x) => `deals.scopes.${x}`),
      ...SECTIONS.flatMap((x) => [`deals.sections.${x}`, `deals.sectionHints.${x}`]),
      ...SLAB_MODES.map((x) => `deals.slabModes.${x}`),
      ...SLAB_PERIODS.map((x) => `deals.slabPeriods.${x}`),
      ...VALIDATION_CODES.map((x) => `deals.validation.${x}`),
      ...BREAKDOWN_KEYS.map((x) => `deals.breakdown.${x}`),
      ...["per_unit_paise", "per_month_paise", "lifetime_paise"].map((x) => `deals.caps.${x}`),
      ...["pct_of_fixed", "pct_of_commission"].map((x) => `deals.summary.bonusPct.${x}`),
      ...["terms", "versions", "dryRun", "details"].map((x) => `deals.tabs.${x}`),
      ...[
        "leads",
        "qualified_leads",
        "applications",
        "enrollments",
        "cancellations",
        "views",
        "days_late",
        "disclosure_issues",
        "months",
        "commission_received",
        "has_pan",
        "gst_registered",
      ].map((x) => `deals.scenario.${x}`),
      ...["week", "month"].map((x) => `deals.builder.${x}`),
      ...CONTRACT_STATUSES.map((x) => `contracts.statuses.${x}`),
      ...["original", "amendment", "renewal"].map((x) => `contracts.kinds.${x}`),
      ...["creator", "agency", "eduwit"].map((x) => `contracts.sides.${x}`),
      ...CONTRACT_TABS.map((x) => `contracts.tabs.${x}`),
      ...EDITABLE_CATEGORIES.map((x) => `contracts.categories.${x}`),
      ...["contracts", "templates", "clauses"].map((x) => `contracts.area.${x}`),
      ...["creator", "deal", "campaign", "eduwit", "contract"].map((x) => `contracts.editor.groups.${x}`),
      ...["all", "unreviewed", "archived"].map((x) => `contracts.library.filters.${x}`),
      ...SAMPLE_KINDS.map((x) => `contracts.templates.samples.${x}`),
      ...["added", "removed", "changed", "same"].map((x) => `contracts.versions.changes.${x}`),
      ...["pending", "accepted", "rejected", "countered", "withdrawn"].map((x) => `contracts.requests.statuses.${x}`),
      ...["creator", "agency", "signatory"].map((x) => `contracts.record.roles.${x}`),
      ...["void", "terminated", "completed"].flatMap((x) => [`contracts.actions.${x}`, `contracts.actions.${x}Hint`]),
      ...CONTRACT_DB_ERRORS.map(([, k]) => `contracts.errors.${k}`),
      ...["unknown_item", "invalid_value", "no_change", "invalid_config"].map((x) => `contracts.errors.counter.${x}`),
      ...SIGN_ERRORS.map((x) => `contracts.sign.errors.${x}`),
      ...SIGN_CHANNELS.map((x) => `contracts.sign.channels.${x}`),
    ];
    for (const k of keys) expect(has(k), k).toBe(true);
  });

  it("describes every role", () => {
    for (const r of STAFF_ROLES) expect(has(`roles.descriptions.${r}`)).toBe(true);
  });

  it("labels every setting field and option", () => {
    const walk = (s: Record<string, unknown>): void => {
      for (const [k, v] of Object.entries((s.properties ?? {}) as Record<string, Record<string, unknown>>)) {
        expect(has(`settingFields.${k}`), k).toBe(true);
        walk(v);
      }
      const items = s.items as Record<string, unknown> | undefined;
      if (items) walk(items);
      for (const e of (s.enum ?? []) as unknown[])
        if (typeof e === "string" && /^[a-z_]+$/.test(e)) expect(has(`settingOptions.${e}`), e).toBe(true);
      for (const a of (s.anyOf ?? []) as Record<string, unknown>[]) walk(a);
    };
    for (const key of SETTING_KEYS) walk(settingJsonSchema(key));
  });
});
