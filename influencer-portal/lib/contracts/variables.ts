// Contract variables (spec 8.1): the catalogue shown in the template editor's picker, and the context built for one
// contract. Every amount comes from the deal's compensation config; nothing is typed by hand.
import type { DeliverableItem } from "@/lib/campaigns/schemas";
import { fixedValue, type CompConfig, type Trigger } from "@/lib/compensation/schema";
import { formatDate, formatNumber, formatPaise } from "@/lib/format";
import type { TableValue, TemplateContext } from "./template";

export type VariableKind = "text" | "flag" | "table";
export interface VariableDef {
  key: string;
  label: string;
  kind: VariableKind;
  group: "creator" | "deal" | "eduwit" | "contract" | "campaign";
}

export const VARIABLES: readonly VariableDef[] = [
  {
    key: "creator.legal_name",
    label: "Creator's legal name (as on PAN)",
    kind: "text",
    group: "creator",
  },
  { key: "creator.display_name", label: "Creator's display name", kind: "text", group: "creator" },
  { key: "creator.handle", label: "Creator's handle", kind: "text", group: "creator" },
  { key: "creator.address", label: "Creator's city and state", kind: "text", group: "creator" },
  { key: "creator.email", label: "Creator's email", kind: "text", group: "creator" },
  { key: "creator.pan_masked", label: "Creator's PAN (masked)", kind: "text", group: "creator" },
  { key: "creator.gstin", label: "Creator's GSTIN", kind: "text", group: "creator" },
  {
    key: "creator.gst_registered",
    label: "Creator is GST-registered",
    kind: "flag",
    group: "creator",
  },
  { key: "payee.name", label: "Payee (who is paid)", kind: "text", group: "creator" },
  { key: "payee.is_agency", label: "Payee is an agency", kind: "flag", group: "creator" },
  { key: "deal.code", label: "Deal reference", kind: "text", group: "deal" },
  { key: "deal.title", label: "Deal title", kind: "text", group: "deal" },
  { key: "deal.start_date", label: "Start date", kind: "text", group: "deal" },
  { key: "deal.end_date", label: "End date", kind: "text", group: "deal" },
  {
    key: "deal.model",
    label: "Deal type (commission_only, fixed_only, hybrid, barter, custom)",
    kind: "text",
    group: "deal",
  },
  { key: "deal.has_fixed", label: "Deal has fixed fees", kind: "flag", group: "deal" },
  { key: "deal.has_commission", label: "Deal has commission", kind: "flag", group: "deal" },
  { key: "deal.has_bonuses", label: "Deal has bonuses", kind: "flag", group: "deal" },
  { key: "deal.has_penalties", label: "Deal has penalties", kind: "flag", group: "deal" },
  {
    key: "deal.has_fees",
    label: "Deal has usage, exclusivity or other fees",
    kind: "flag",
    group: "deal",
  },
  { key: "deal.has_exclusivity", label: "Deal includes exclusivity", kind: "flag", group: "deal" },
  {
    key: "deal.has_recoupment",
    label: "Commission is recouped against the fixed fee",
    kind: "flag",
    group: "deal",
  },
  { key: "deal.fixed_fee_total", label: "Total fixed fees", kind: "text", group: "deal" },
  { key: "deal.recoupment_text", label: "Recoupment wording", kind: "text", group: "deal" },
  {
    key: "deal.milestone_table",
    label: "Table: fixed fees and milestones",
    kind: "table",
    group: "deal",
  },
  { key: "deal.commission_table", label: "Table: commission rules", kind: "table", group: "deal" },
  { key: "deal.bonus_table", label: "Table: bonuses", kind: "table", group: "deal" },
  { key: "deal.penalty_table", label: "Table: penalties", kind: "table", group: "deal" },
  { key: "deal.fee_table", label: "Table: additional fees", kind: "table", group: "deal" },
  { key: "deliverables_table", label: "Table: deliverables", kind: "table", group: "deal" },
  { key: "campaign.name", label: "Campaign name", kind: "text", group: "campaign" },
  { key: "eduwit.legal_name", label: "Eduwit's legal name", kind: "text", group: "eduwit" },
  { key: "eduwit.address", label: "Eduwit's address", kind: "text", group: "eduwit" },
  { key: "eduwit.gstin", label: "Eduwit's GSTIN", kind: "text", group: "eduwit" },
  { key: "eduwit.pan", label: "Eduwit's PAN", kind: "text", group: "eduwit" },
  { key: "eduwit.support_email", label: "Eduwit's contact email", kind: "text", group: "eduwit" },
  {
    key: "eduwit.signatory_name",
    label: "Authorised Signatory's name",
    kind: "text",
    group: "eduwit",
  },
  {
    key: "eduwit.signatory_designation",
    label: "Authorised Signatory's designation",
    kind: "text",
    group: "eduwit",
  },
  { key: "contract.number", label: "Contract number", kind: "text", group: "contract" },
  { key: "contract.date", label: "Contract date", kind: "text", group: "contract" },
  {
    key: "contract.is_amendment",
    label: "This contract amends an earlier one",
    kind: "flag",
    group: "contract",
  },
  {
    key: "contract.parent_number",
    label: "Number of the contract being amended",
    kind: "text",
    group: "contract",
  },
];
export const VARIABLE_KEYS: ReadonlySet<string> = new Set(VARIABLES.map((v) => v.key));

const money = (p: number) => formatPaise(p, { whole: p % 100 === 0 });

export function triggerText(t: Trigger): string {
  const d = "deliverable" in t && t.deliverable ? ` (${t.deliverable})` : "";
  switch (t.type) {
    case "on_contract_signed":
      return "on signing this agreement";
    case "on_brief_acknowledged":
      return "when the brief is acknowledged";
    case "on_concept_approved":
      return `when the concept is approved${d}`;
    case "on_draft_approved":
      return `when the draft is approved${d}`;
    case "on_deliverable_live":
      return `when the content is live${d}`;
    case "after_n_days_live":
      return `${String(t.days)} days after the content is live${d}`;
    case "on_metric_threshold":
      return `when ${t.metric} reach ${formatNumber(t.threshold)}${d}`;
    case "on_campaign_end":
      return "at the end of the campaign";
    case "on_specific_date":
      return `on ${formatDate(t.date)}`;
    case "manual_release":
      return "on release by Eduwit";
  }
}

const BASIS: Record<CompConfig["commission"][number]["basis"]["type"], string> = {
  flat_per_enrollment: "per enrolment",
  pct_of_eduwit_commission: "of Eduwit's commission per enrolment",
  pct_of_programme_fee: "of the programme fee per enrolment",
  flat_per_qualified_lead: "per qualified lead",
  flat_per_lead: "per lead",
  flat_per_application: "per application",
};

const CONFIRMATION: Record<CompConfig["commission"][number]["confirmation"]["type"], string> = {
  immediate: "on accrual",
  after_hold_days: "after the hold period",
  on_eduwit_commission_received: "when Eduwit receives its commission",
};

export function milestoneTable(c: CompConfig): TableValue {
  const rows: string[][] = [];
  for (const f of c.fixed) {
    const total = f.amount_paise * f.units;
    if (f.basis === "retainer" && f.retainer) {
      rows.push([
        f.label,
        `${money(f.amount_paise)} per ${f.retainer.every} × ${String(f.retainer.periods)}`,
        `at the ${f.retainer.pay_on === "period_start" ? "start" : "end"} of each period`,
        `${String(f.retainer.payment_terms_days)} days`,
      ]);
      continue;
    }
    for (const m of f.milestones) {
      const amount =
        m.share.type === "pct"
          ? `${money(Math.round((total * m.share.pct) / 100))} (${String(m.share.pct)}%)`
          : money(m.share.amount_paise);
      const cancel =
        m.on_cancel.type === "pay_pct" ? `; ${String(m.on_cancel.pct)}% if cancelled` : "";
      rows.push([
        `${f.label}: ${m.label}`,
        amount,
        triggerText(m.trigger) + cancel,
        `${String(m.due_offset_days + m.payment_terms_days)} days`,
      ]);
    }
  }
  return { head: ["Payment", "Amount", "Payable", "Due within"], rows };
}

export function commissionTable(c: CompConfig): TableValue {
  const rows = c.commission.map((r) => {
    const rate =
      "amount_paise" in r.basis ? money(r.basis.amount_paise) : `${String(r.basis.pct)}%`;
    const base =
      r.basis.type === "pct_of_eduwit_commission"
        ? r.basis.base === "net_of_gst"
          ? " (net of GST)"
          : " (including GST)"
        : "";
    const extras: string[] = [];
    if (r.scope.type !== "all") extras.push(`only ${r.scope.type}`);
    if (r.slabs)
      extras.push(
        `${r.slabs.mode} slabs per ${r.slabs.period}: ` +
          r.slabs.tiers
            .map(
              (t) =>
                `from #${String(t.from)} ${t.amount_paise !== undefined ? money(t.amount_paise) : `${String(t.pct ?? 0)}%`}`,
            )
            .join(", "),
      );
    if (r.caps.per_unit_paise !== undefined)
      extras.push(`max ${money(r.caps.per_unit_paise)} each`);
    if (r.caps.per_month_paise !== undefined)
      extras.push(`max ${money(r.caps.per_month_paise)} per month`);
    if (r.caps.lifetime_paise !== undefined)
      extras.push(`max ${money(r.caps.lifetime_paise)} in total`);
    if (r.clawback_window_days !== undefined)
      extras.push(`clawback within ${String(r.clawback_window_days)} days`);
    return [
      r.label,
      `${rate} ${BASIS[r.basis.type]}${base}`,
      CONFIRMATION[r.confirmation.type],
      extras.join("; ") || "—",
    ];
  });
  for (const f of c.floors)
    rows.push([
      f.label,
      `minimum ${money(f.amount_paise)} per ${f.period === "month" ? "month" : "deal"}`,
      "at period end",
      "topped up against commission",
    ]);
  return { head: ["Rule", "Rate", "Confirmed", "Conditions"], rows };
}

export function bonusTable(c: CompConfig): TableValue {
  return {
    head: ["Bonus", "Amount", "Condition", "Window"],
    rows: c.bonuses.map((b) => [
      b.label,
      b.amount.type === "fixed"
        ? money(b.amount.amount_paise)
        : `${String(b.amount.pct)}% of ${b.amount.type === "pct_of_fixed" ? "the fixed fee" : "commission in the window"}`,
      b.conditions.items
        .map(
          (x) =>
            `${x.metric.replace(/_/g, " ")} ${x.comparator === "gte" ? "≥" : "≤"} ${formatNumber(x.value)}`,
        )
        .join(b.conditions.op === "and" ? " and " : " or "),
      (b.window.type === "dates"
        ? `${formatDate(b.window.from)} to ${formatDate(b.window.to)}`
        : b.window.type) + (b.repeat === "every" ? ", each window" : ""),
    ]),
  };
}

export function penaltyTable(c: CompConfig): TableValue {
  return {
    head: ["Penalty", "Amount"],
    rows: c.penalties.map((p) => [
      p.label,
      p.type === "late_delivery"
        ? `${p.per_day.type === "pct" ? `${String(p.per_day.pct)}% of the linked milestones` : money(p.per_day.amount_paise)} per day late after ${String(p.grace_days)} grace days${p.cap ? `, capped at ${p.cap.type === "amount" ? money(p.cap.amount_paise) : `${String(p.cap.pct)}%`}` : ""}`
        : p.type === "missed_deliverable"
          ? p.action.type === "fixed"
            ? money(p.action.amount_paise)
            : "linked milestones are forfeited"
          : p.type === "disclosure"
            ? money(p.amount_paise)
            : `${String(p.pct)}% of fixed fees already earned`,
    ]),
  };
}

export function feeTable(c: CompConfig): TableValue {
  return {
    head: ["Fee", "Amount", "Terms", "Payable"],
    rows: c.fees.map((f) => [
      f.label,
      money(f.amount_paise),
      [
        f.platforms.length ? f.platforms.join(", ") : "",
        f.duration_days ? `${String(f.duration_days)} days` : "",
        f.category ?? "",
      ]
        .filter(Boolean)
        .join("; ") || "—",
      triggerText(f.trigger),
    ]),
  };
}

export function deliverablesTable(items: readonly DeliverableItem[]): TableValue {
  return {
    head: ["Platform", "Format", "Count"],
    rows: items.map((d) => [
      d.platform.replace(/_/g, " "),
      d.format.replace(/_/g, " "),
      String(d.count),
    ]),
  };
}

export interface ContextInput {
  creator: {
    legal_name: string | null;
    display_name: string;
    handle: string;
    city: string | null;
    state: string | null;
    email: string | null;
    pan_masked: string | null;
    gstin: string | null;
  };
  payee: { name: string; is_agency: boolean };
  deal: {
    code: string;
    title: string;
    starts_on: string;
    ends_on: string | null;
    model: string;
    config: CompConfig;
  };
  deliverables: readonly DeliverableItem[];
  campaign: { name: string } | null;
  eduwit: {
    legal_name: string;
    address: string;
    gstin: string;
    pan: string;
    support_email: string;
  };
  signatory: { name: string; designation: string } | null;
  contract: { number: string; date: string; parent_number: string | null };
}

export function buildContext(i: ContextInput): TemplateContext {
  const c = i.deal.config;
  const fixed = fixedValue(c);
  const recoupable = c.recoupment.mode === "none" ? 0 : fixedValue(c, c.recoupment.fixed);
  return {
    "creator.legal_name": i.creator.legal_name,
    "creator.display_name": i.creator.display_name,
    "creator.handle": `@${i.creator.handle}`,
    "creator.address": [i.creator.city, i.creator.state].filter(Boolean).join(", ") || null,
    "creator.email": i.creator.email,
    "creator.pan_masked": i.creator.pan_masked,
    "creator.gstin": i.creator.gstin,
    "creator.gst_registered": !!i.creator.gstin,
    "payee.name": i.payee.name,
    "payee.is_agency": i.payee.is_agency,
    "deal.code": i.deal.code,
    "deal.title": i.deal.title,
    "deal.start_date": formatDate(i.deal.starts_on),
    "deal.end_date": i.deal.ends_on ? formatDate(i.deal.ends_on) : null,
    "deal.model": i.deal.model,
    "deal.has_fixed": c.fixed.length > 0,
    "deal.has_commission": c.commission.length > 0,
    "deal.has_bonuses": c.bonuses.length > 0,
    "deal.has_penalties": c.penalties.length > 0,
    "deal.has_fees": c.fees.length > 0,
    "deal.has_exclusivity": c.fees.some((f) => f.kind === "exclusivity"),
    "deal.has_recoupment": c.recoupment.mode !== "none",
    "deal.fixed_fee_total": fixed ? money(fixed) : null,
    "deal.recoupment_text":
      c.recoupment.mode === "none"
        ? null
        : c.recoupment.mode === "full"
          ? `Commission is first set off against the fixed fees of ${money(recoupable)}; commission above that amount is payable.`
          : `Commission is first set off against ${String(c.recoupment.pct)}% of the fixed fees of ${money(recoupable)}; commission above that amount is payable.`,
    "deal.milestone_table": milestoneTable(c),
    "deal.commission_table": commissionTable(c),
    "deal.bonus_table": bonusTable(c),
    "deal.penalty_table": penaltyTable(c),
    "deal.fee_table": feeTable(c),
    deliverables_table: deliverablesTable(i.deliverables),
    "campaign.name": i.campaign?.name ?? null,
    "eduwit.legal_name": i.eduwit.legal_name,
    "eduwit.address": i.eduwit.address || null,
    "eduwit.gstin": i.eduwit.gstin || null,
    "eduwit.pan": i.eduwit.pan || null,
    "eduwit.support_email": i.eduwit.support_email || null,
    "eduwit.signatory_name": i.signatory?.name ?? null,
    "eduwit.signatory_designation": i.signatory?.designation ?? null,
    "contract.number": i.contract.number,
    "contract.date": formatDate(i.contract.date),
    "contract.is_amendment": i.contract.parent_number !== null,
    "contract.parent_number": i.contract.parent_number,
  };
}
