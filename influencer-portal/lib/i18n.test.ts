// Every translation key used in code exists in messages/en.json, and every setting field has a label.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { createTranslator } from "next-intl";
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
  CREATOR_TABS,
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
import { BOARD_COLUMNS } from "@/lib/content/board";
import { ASCI_CHECKLIST } from "@/lib/content/compliance";
import { BRIEF_STATES, DELIVERABLE_VIEWS, METRIC_FIELDS, PENALTY_STATUSES } from "@/lib/content/data";
import { CONTENT_DB_ERRORS } from "@/lib/content/schemas";
import { ACTIONS, DELIVERABLE_STATUSES, DUE_STAGES, STAGES } from "@/lib/content/workflow";
import { ATTRIBUTION_STATUSES, REASONS } from "@/lib/attribution/rules";
import { CREATOR_STAGES, OPEN_STAGES, STAGE_FIELDS } from "@/lib/attribution/stages";
import { DESTINATIONS } from "@/lib/attribution/links";
import { FRAUD_SIGNALS } from "@/lib/attribution/fraud";
import { ATTRIBUTION_DB_ERRORS } from "@/lib/attribution/schemas";
import { LEAD_FIELD_ORDER } from "@/components/leads/lead-detail";
import { feedRow } from "@/lib/leads/data";
import { FINANCE_AREAS } from "@/components/finance/finance-nav";
import { TDS_COMPONENTS } from "@/lib/compensation/tax";
import { BATCH_STATUSES, PAYOUT_STATUSES } from "@/lib/ledger/data";
import { INVOICE_PROBLEMS } from "@/lib/ledger/invoice";
import { ENTRY_STATUSES, LEDGER_TYPES } from "@/lib/ledger/lifecycle";
import { RECEIPT_STATUSES } from "@/lib/ledger/schemas";
import { LEDGER_DB_ERRORS } from "@/lib/ledger/schemas";
import { OBLIGATION_KINDS } from "@/lib/compliance/obligations";
import { ERASED, RETAINED } from "@/lib/privacy/plan";
import { myRequest } from "@/lib/privacy/data";
import { RECOMMENDATION_CODES } from "@/lib/scorecards/recommend";
import { INSIGHT_DB_ERRORS } from "@/lib/scorecards/schemas";
import { SCORE_PARTS } from "@/lib/scorecards/score";
import { entryRules, PAYOUT_CYCLES } from "@/lib/scorecards/tiers";
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
  for (const f of sources) {
    const src = readFileSync(f, "utf8");
    for (const m of src.matchAll(/\bt\("([a-zA-Z0-9_.]+)"/g)) keys.add(m[1] ?? "");
    // Both branches of t(cond ? "a.b" : "c.d").
    for (const m of src.matchAll(/\bt\([^"()]*\?\s*"(\w+\.[\w.]+)"\s*:\s*"(\w+\.[\w.]+)"/g)) {
      keys.add(m[1] ?? "");
      keys.add(m[2] ?? "");
    }
  }

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
      ...CREATOR_TABS.map((x) => `creators.tabs.${x}`),
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

  it("labels every content status, action, stage, check and error", () => {
    const keys = [
      ...DELIVERABLE_STATUSES.map((x) => `content.statuses.${x}`),
      ...ACTIONS.map((x) => `content.actions.${x}`),
      ...STAGES.flatMap((x) => [`content.stages.${x}`, `content.stageHints.${x}`]),
      ...DUE_STAGES.flatMap((x) => [`content.dueStages.${x}`, `content.next.${x}`]),
      ...BOARD_COLUMNS.map((x) => `content.board.${x}`),
      ...DELIVERABLE_VIEWS.filter((x) => x !== "all").map(
        (x) => `content.${x === "open" ? "empty" : `empty${x[0]?.toUpperCase() ?? ""}${x.slice(1)}`}`,
      ),
      ...BRIEF_STATES.map((x) => `content.briefs.states.${x}`),
      ...PENALTY_STATUSES.map((x) => `content.penalties.statuses.${x}`),
      ...METRIC_FIELDS.map((x) => `content.metrics.fields.${x}`),
      ...ASCI_CHECKLIST.map((x) => `content.asci.items.${x}`),
      ...["banned_claims", "disclosure", "asci_checklist"].map((x) => `content.checks.${x}`),
      ...["block", "warn"].map((x) => `content.checks.severity.${x}`),
      ...["concept", "draft"].flatMap((x) => [
        `content.kinds.${x}`,
        `content.submit.body.${x}`,
        `content.submit.bodyHint.${x}`,
        `content.submit.send.${x}`,
      ]),
      ...["submitted", "approved", "changes_requested"].map((x) => `content.submissionStatus.${x}`),
      ...["pending", "verified", "rejected", "replaced"].map((x) => `content.live.statuses.${x}`),
      ...["live", "disclosure", "matches"].map((x) => `content.live.verifyItems.${x}`),
      ...["manual", "screenshot", "api"].map((x) => `content.metrics.sources.${x}`),
      ...["creator", "agency", "eduwit"].map((x) => `content.qa.sides.${x}`),
      ...["creator", "agency", "eduwit", "system"].map((x) => `content.history.sides.${x}`),
      ...["todo", "waiting", "done"].map((x) => `content.my.groups.${x}`),
      ...["review", "live", "metrics", "history", "settings"].map((x) => `content.tabs.${x}`),
      ...["edit", "preview", "versions"].map((x) => `content.briefs.tabs.${x}`),
      ...["deliverables", "review", "overdue", "live", "claims", "penalties"].map((x) => `content.area.${x}`),
      ...CONTENT_DB_ERRORS.map(([, k]) => `content.errors.${k}`),
      ...["invalid", "not_https", "wrong_platform"].map((x) => `content.errors.url.${x}`),
    ];
    for (const k of keys) expect(has(k), k).toBe(true);
  });

  it("labels every lead stage, status, reason, field, signal and error", () => {
    const keys = [
      ...[...OPEN_STAGES, "enrolled", "closed"].map((x) => `leads.columns.${x}`),
      ...CREATOR_STAGES.map((x) => `leads.stages.names.${x}`),
      ...ATTRIBUTION_STATUSES.map((x) => `leads.status.${x}`),
      ...REASONS.map((x) => `leads.reasons.${x}`),
      ...feedRow.shape.earning_status.options.map((x) => `leads.earning.${x}`),
      ...LEAD_FIELD_ORDER.map((x) => `leads.fields.${x}`),
      ...STAGE_FIELDS.map((x) => `leads.stages.fields.${x}`),
      ...["in", "present", "empty", "is_true"].map((x) => `leads.stages.modes.${x}`),
      ...FRAUD_SIGNALS.flatMap((x) => [`leads.signals.${x}`, `leads.signalDetail.${x}`]),
      ...["open", "cleared", "confirmed", "all"].map((x) => `leads.fraud.statuses.${x}`),
      ...["all", "fraud", "stages", "tools"].map((x) => `leads.area.${x}`),
      ...["cancelled", "under_review"].map((x) => `leads.flags.${x}`),
      ...["staff", "system"].map((x) => `leads.actor.${x}`),
      ...DESTINATIONS.flatMap((x) => [`links.destinations.${x}`, `links.destinationHints.${x}`]),
      ...ATTRIBUTION_DB_ERRORS.map(([, k]) => `leads.errors.${k}`),
    ];
    for (const k of keys) expect(has(k), k).toBe(true);
  });

  it("labels every ledger type, status and error", () => {
    const keys = [
      ...LEDGER_TYPES.map((x) => `finance.types.${x}`),
      ...ENTRY_STATUSES.map((x) => `finance.statuses.${x}`),
      ...LEDGER_DB_ERRORS.map(([, k]) => `finance.errors.${k}`),
      ...["changed", "obsolete"].map((x) => `finance.deal.reasons.${x}`),
      ...FINANCE_AREAS.map((x) => `finance.area.${x.key}`),
      ...TDS_COMPONENTS.map((x) => `finance.components.${x}`),
      ...BATCH_STATUSES.map((x) => `finance.batchStatuses.${x}`),
      ...PAYOUT_STATUSES.map((x) => `finance.payoutStatuses.${x}`),
      ...["submitted", "accepted", "rejected"].map((x) => `finance.invoiceStatuses.${x}`),
      ...["creator_gst_invoice", "payout_statement"].map((x) => `finance.invoiceKinds.${x}`),
      ...[...RECEIPT_STATUSES, "none"].map((x) => `finance.receiptStatuses.${x}`),
      ...["missing_column", "bad_ref", "bad_utr", "bad_date", "future_date", "duplicate", "file"].map(
        (x) => `finance.utr.${x}`,
      ),
      ...["gross_paise", "tds_paise", "gst_paise", "net_paise"].map((x) => `finance.payouts.totals.${x}`),
      ...["overdue", "received_not_confirmed"].map((x) => `finance.receipts.flags.${x}`),
      ...["remove", "fail"].flatMap((x) => [
        `finance.payouts.${x}`,
        `finance.payouts.${x}Title`,
        `finance.payouts.${x}Hint`,
      ]),
      ...["approved", "firstApproval"].map((x) => `finance.payouts.${x}`),
      ...["accepted", "rejected"].map((x) => `finance.invoices.${x}`),
      ...INVOICE_PROBLEMS.map((x) => `earnings.invoice.problems.${x}`),
    ];
    for (const k of keys) expect(has(k), k).toBe(true);
  });

  it("labels every scorecard part, tier rule, recommendation, obligation and privacy value", () => {
    const rules = Object.keys(entryRules.shape);
    const keys = [
      ...SCORE_PARTS.map((x) => `insight.parts.${x}`),
      ...rules.flatMap((x) => [`insight.rules.${x}`, `insight.rulesShort.${x}`]),
      ...rules.filter((x) => x !== "demote_after_months").map((x) => `insight.home.rules.${x}`),
      ...PAYOUT_CYCLES.map((x) => `insight.cycles.${x}`),
      ...["eligible", "below_rules", "manual", "manual_ended"].map((x) => `insight.history.${x}`),
      ...RECOMMENDATION_CODES.flatMap((x) => [
        `insight.recommend.codes.${x}.title`,
        `insight.recommend.codes.${x}.why`,
      ]),
      ...INSIGHT_DB_ERRORS.map(([, k]) => `insight.errors.${k}`),
      ...OBLIGATION_KINDS.map((x) => `compliance.kinds.${x}`),
      ...["met", "missed", "open", "waived"].map((x) => `compliance.status.${x}`),
      ...myRequest.shape.kind.options.flatMap((x) => [`privacy.kinds.${x}`, `privacy.requested.${x}`]),
      ...myRequest.shape.status.options.map((x) => `privacy.statuses.${x}`),
      ...[...ERASED, ...RETAINED].map((x) => `privacy.parts.${x}`),
      ...["exportDaily", "deletionOpen", "openDeals", "balance", "decided", "reason"].map((x) => `privacy.errors.${x}`),
    ];
    for (const k of keys) expect(has(k), k).toBe(true);
  });

  it("shows template placeholders literally where a hint explains them", () => {
    const tr = createTranslator({ locale: "en", messages: en });
    expect(tr("campaigns.tracking.messageHint")).toContain("{code}");
    expect(tr("campaigns.tracking.needsCode")).toContain("{code}");
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
