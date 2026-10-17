// The brief (spec 10.1). A brief version is one structured document: fields for objective, audience, claims,
// disclosures, do's and don'ts, deliverables, references, assets, hashtags, the call to action and FAQs, with rich
// text (the contract document model, D-81) for the key messages. Templates hold the defaults; `buildBrief` fills a
// new brief from a template, the campaign, the deal and the catalogue. Pure.
import { z } from "zod";
import { deliverableItem, type DeliverableItem } from "@/lib/campaigns/schemas";
import { CONTENT_FORMATS, PLATFORMS, type ContentFormat } from "@/lib/creators/schemas";
import { EMPTY_DOC, richDoc } from "@/lib/contracts/doc";
import { formatRupees } from "@/lib/format";
import { DEFAULT_TOGGLES, STAGES, type StageToggles } from "./workflow";

const line = z.string().trim().min(1).max(300);
const list = (max: number) => z.array(line).max(max).default([]);
const httpsUrl = z
  .string()
  .trim()
  .max(1000)
  .refine((u) => /^https:\/\/[^\s/]+\.[^\s]+$/i.test(u), "https");

export const briefDeliverable = z.object({
  platform: z.enum(PLATFORMS),
  format: z.enum(CONTENT_FORMATS),
  count: z.number().int().min(1).max(50),
  /** Seconds, for video formats. */
  duration_s: z.number().int().min(1).max(7200).nullable().default(null),
  aspect_ratio: z.string().trim().max(10).nullable().default(null),
  notes: z.string().trim().max(500).default(""),
});
export type BriefDeliverable = z.infer<typeof briefDeliverable>;

/** Days from the brief's acknowledgement (or the deal start) to each due date. */
export const dueOffsets = z.object({
  concept: z.number().int().min(0).max(365).default(5),
  draft: z.number().int().min(0).max(365).default(10),
  live: z.number().int().min(0).max(365).default(15),
  metrics: z.number().int().min(0).max(365).default(22),
});
export type DueOffsets = z.infer<typeof dueOffsets>;

export const stageToggles = z.object(
  Object.fromEntries(STAGES.map((s) => [s, z.boolean().default(DEFAULT_TOGGLES[s])])) as Record<
    (typeof STAGES)[number],
    z.ZodDefault<z.ZodBoolean>
  >,
);

export const briefContent = z.object({
  objective: z.string().trim().max(2000).default(""),
  audience: z.string().trim().max(2000).default(""),
  key_messages: richDoc.default(EMPTY_DOC),
  /** Programmes from the catalogue (shown with live details). */
  programme_ids: z.array(z.number().int().positive()).max(30).default([]),
  /** Factual claims the creator may make, generated from the catalogue and editable. */
  approved_claims: list(100),
  /** The banned claims in force when the version was published (the scan always uses the live list). */
  banned_claims: list(200),
  disclosures: list(20),
  dos: list(30),
  donts: list(30),
  tone: z.string().trim().max(300).default(""),
  languages: list(10),
  deliverables: z.array(briefDeliverable).max(30).default([]),
  references: z
    .array(z.object({ label: line, url: httpsUrl }))
    .max(30)
    .default([]),
  /** Files in the inf-briefs bucket (logos, fonts, b-roll, moodboard images). */
  assets: z
    .array(
      z.object({ label: line, path: z.string().regex(/^[0-9a-f-]{36}\/[A-Za-z0-9._-]{1,120}$/) }),
    )
    .max(30)
    .default([]),
  hashtags: list(30),
  mentions: list(30),
  cta: z.object({ text: z.string().trim().max(300).default("") }).default({ text: "" }),
  faqs: z
    .array(z.object({ q: line, a: z.string().trim().min(1).max(2000) }))
    .max(30)
    .default([]),
});
export type BriefContent = z.infer<typeof briefContent>;

/** A template: the defaults copied into each new brief, plus the workflow set-up for its deliverables. */
export const briefTemplateContent = briefContent
  .omit({ programme_ids: true, approved_claims: true, banned_claims: true, deliverables: true })
  .extend({
    due_offsets: dueOffsets.default(dueOffsets.parse({})),
    stages: stageToggles.default(stageToggles.parse({})),
  });
export type BriefTemplateContent = z.infer<typeof briefTemplateContent>;

const ASPECT: Partial<Record<ContentFormat, string>> = {
  reel: "9:16",
  short: "9:16",
  story: "9:16",
  post: "4:5",
  carousel: "4:5",
  youtube_video: "16:9",
};
const DURATION: Partial<Record<ContentFormat, number>> = {
  reel: 60,
  short: 60,
  story: 15,
  youtube_video: 480,
};

/** Brief deliverable specs from the agreed deliverables, with sensible format defaults. */
export function deliverableSpecs(items: readonly DeliverableItem[]): BriefDeliverable[] {
  return items.map((d) => ({
    platform: d.platform,
    format: d.format,
    count: d.count,
    duration_s: DURATION[d.format] ?? null,
    aspect_ratio: ASPECT[d.format] ?? null,
    notes: "",
  }));
}

export interface CatalogueProgramme {
  id: number;
  program_name: string;
  specialization: string | null;
  level: string | null;
  mode: string | null;
  university: string;
  recognitions: string[] | null;
  accreditation_text: string | null;
  fee_total: number | null;
  fee_yearly: number | null;
  min_qualification: string | null;
  min_pct_general: number | null;
  eligibility_text: string | null;
}

/** Factual claims from a catalogue programme (fees, mode, recognitions, eligibility). Only what the catalogue says. */
export function approvedClaims(p: CatalogueProgramme): string[] {
  const name = `${p.university} ${p.program_name}${p.specialization ? ` (${p.specialization})` : ""}`;
  const out: string[] = [];
  const kind = [p.mode?.toLowerCase(), p.level].filter(Boolean).join(" ");
  if (kind) out.push(`${name} is ${/^[aeiou]/i.test(kind) ? "an" : "a"} ${kind} programme.`);
  if (p.fee_total !== null && p.fee_total > 0)
    out.push(`${name}: total fee ${formatRupees(p.fee_total, { whole: true })}.`);
  else if (p.fee_yearly !== null && p.fee_yearly > 0)
    out.push(`${name}: fee ${formatRupees(p.fee_yearly, { whole: true })} per year.`);
  if (p.recognitions?.length)
    out.push(`${p.university} is recognised by ${p.recognitions.join(", ")}.`);
  if (p.accreditation_text) out.push(`${p.university}: ${p.accreditation_text.trim()}`);
  if (p.min_qualification)
    out.push(
      `${name} eligibility: ${p.min_qualification}${p.min_pct_general !== null ? ` with at least ${String(p.min_pct_general)}%` : ""}.`,
    );
  else if (p.eligibility_text) out.push(`${name} eligibility: ${p.eligibility_text.trim()}`);
  return out.map((s) => s.slice(0, 300));
}

export interface BuildBriefInput {
  template: BriefTemplateContent;
  campaign: {
    objective_text: string | null;
    description: string | null;
    deliverables: readonly DeliverableItem[];
  } | null;
  /** Deliverables agreed on the deal (they win over the campaign's). */
  agreed: readonly DeliverableItem[];
  programmes: readonly CatalogueProgramme[];
  banned: readonly string[];
  disclosureTerms: readonly string[];
}

/** A new brief from its template, the campaign, the deal's agreed deliverables and the catalogue. */
export function buildBrief(i: BuildBriefInput): BriefContent {
  const t = i.template;
  const items = i.agreed.length ? i.agreed : (i.campaign?.deliverables ?? []);
  const disclosures = t.disclosures.length
    ? t.disclosures
    : [
        `Disclose the paid partnership at the start, e.g. ${i.disclosureTerms.slice(0, 2).join(" or ")}.`,
      ];
  return briefContent.parse({
    objective: t.objective || i.campaign?.objective_text || "",
    audience: t.audience,
    key_messages: t.key_messages,
    programme_ids: i.programmes.map((p) => p.id),
    approved_claims: i.programmes.flatMap(approvedClaims).slice(0, 100),
    banned_claims: i.banned.slice(0, 200),
    disclosures,
    dos: t.dos,
    donts: t.donts,
    tone: t.tone,
    languages: t.languages,
    deliverables: deliverableSpecs(items.map((d) => deliverableItem.parse(d))),
    references: t.references,
    assets: t.assets,
    hashtags: t.hashtags,
    mentions: t.mentions,
    cta: t.cta,
    faqs: t.faqs,
  });
}

/** Due dates for a deliverable from the offsets, counted from a start instant (ISO, end of that IST day). */
export function dueDatesFrom(
  start: string,
  offsets: DueOffsets,
  toggles: StageToggles,
): Record<string, string> {
  const base = Date.parse(start);
  const at = (days: number) => {
    // 23:59:59 IST on the target day.
    const ist = new Date(base + 330 * 60_000 + days * 86_400_000);
    const ymd = ist.toISOString().slice(0, 10);
    return new Date(`${ymd}T23:59:59+05:30`).toISOString();
  };
  const out: Record<string, string> = {};
  if (toggles.concept) out.concept = at(offsets.concept);
  if (toggles.draft) out.draft = at(offsets.draft);
  out.live = at(offsets.live);
  if (toggles.metrics) out.metrics = at(offsets.metrics);
  return out;
}
