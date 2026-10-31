import {
  CONTRACT_VERSION,
  FACT_KEYS,
  type AnswerMode,
  type Ask,
  type CatalogRow,
  type Classification,
  type Confidence,
  type Eligibility,
  type EventType,
  type FactKey,
  type Intent,
  type Knowledge,
  type Language,
  type Op,
  type Phase,
  type Readiness,
  type Scale,
  type SearchResult,
  type Subject,
} from "./contract";
import { askText, differentCourseText, handoffText, erasureText, stopText } from "./fixed-texts";
import { detectLanguage } from "./language";
import {
  budgetToInr,
  experienceYears,
  normaliseLevel,
  normaliseMode,
  qualificationRank,
  readinessFromTimeline,
  requiredRank,
  scoreToPct,
} from "./normalise";
import { hasFields, type RefRow } from "./placeholders";

/**
 * The decision engine: accepts extracted facts, decides eligibility, readiness, classification, phase, the next ask and
 * the answer mode, chooses catalogue rows, and builds the counselor input and the lead payload.
 *
 * IMPORTANT (docs/AGENT_ARCHITECTURE.md §3.1, APPROVALS A-AGENT-1): Witty's own ENGINE source is not readable from this
 * environment. This is an implementation of Witty's PUBLISHED contract (prompts, enums, observed production data,
 * W1 fixture). Every rule cites its source. `web_advisor_enabled` stays off until this module is replaced by, or proven
 * equivalent to, Witty's ENGINE.
 */
export const ENGINE_VERSION = `${CONTRACT_VERSION}+web.1`;

export interface ProfileEntry {
  value: string | null;
  confirmed?: boolean;
  unsure?: boolean;
  declined?: boolean;
  subject?: Subject;
  scale?: Scale;
}
export type Profile = Partial<Record<FactKey, ProfileEntry>>;

export interface WittyState {
  profile: Profile;
  asks?: Partial<Record<Ask, number>>;
  pending_question?: Ask;
  last_witty_message?: string;
  language?: Language;
  enquirer?: { name: string | null; relation: string } | null;
  phase?: Phase;
  classification?: Classification;
  readiness?: Readiness;
  eligibility?: Eligibility;
  flags?: {
    shown_rows?: number[];
    /** university of each shown row, so "NMIMS wala" resolves (chosen_program) */
    shown_names?: Record<string, string>;
    last_search_key?: string;
    qualified_at?: string;
    escalated?: boolean;
    handoff_offered?: boolean;
    opted_out?: boolean;
    final_program_id?: number;
    alternatives_to?: string;
    supported?: boolean;
  };
  turn?: number;
}

export interface ExtractedFact {
  field: string;
  value: string | number | null;
  evidence?: string;
  op?: Op;
  subject?: Subject;
  scale?: Scale;
  confidence?: Confidence;
}
export interface Extraction {
  facts: ExtractedFact[];
  enquirer?: { name: string | null; relation: string } | null;
  intents: string[];
}

export interface AcceptResult {
  state: WittyState;
  accepted: { field: FactKey; value: string | null; op: Op }[];
  rejected: { field: string; reason: string }[];
  intents: Intent[];
  changed: boolean;
}

/** Fields the website already holds verified (gate): never asked, never overwritten by the chat. */
const WEB_LOCKED: FactKey[] = ["email_id"];

const norm = (s: string) => s.toLowerCase().replace(/\s+/g, " ").trim();

function cloneState(s: WittyState): WittyState {
  return JSON.parse(JSON.stringify({ asks: {}, flags: {}, turn: 0, language: "english", ...s, profile: s.profile ?? {} })) as WittyState;
}

export function value(p: Profile, k: FactKey): string | null {
  const e = p[k];
  return e && !e.declined && !e.unsure && e.value ? e.value : null;
}

/** Fact acceptance (extractor rules: exact evidence, unsure over guessing, declined respected). Source: extractor v6. */
export function acceptFacts(prev: WittyState, x: Extraction, message: string): AcceptResult {
  const state = cloneState(prev);
  const accepted: AcceptResult["accepted"] = [];
  const rejected: AcceptResult["rejected"] = [];
  const msg = norm(message);
  const shown = state.flags?.shown_rows ?? [];
  for (const f of x.facts ?? []) {
    const field = f.field as FactKey;
    if (!(FACT_KEYS as readonly string[]).includes(field)) {
      rejected.push({ field: f.field, reason: "unknown_field" });
      continue;
    }
    if (f.evidence && !msg.includes(norm(f.evidence))) {
      rejected.push({ field, reason: "evidence_not_in_message" });
      continue;
    }
    if (WEB_LOCKED.includes(field) && f.op !== "confirm") {
      rejected.push({ field, reason: "verified_on_web" });
      continue;
    }
    const op: Op = f.confidence === "LOW" && (f.op ?? "set") === "set" ? "unsure" : (f.op ?? "set");
    const raw = f.value === null || f.value === undefined ? null : String(f.value).trim().slice(0, 120);
    const cur = state.profile[field];

    if (field === "chosen_program") {
      const id = resolveChoice(raw ?? "", shown, state);
      if (id) {
        state.flags!.final_program_id = id;
        accepted.push({ field, value: String(id), op: "set" });
      } else rejected.push({ field, reason: "choice_not_resolved" });
      continue;
    }
    if (op === "declined") {
      state.profile[field] = { value: null, declined: true };
      accepted.push({ field, value: null, op });
      continue;
    }
    if (op === "negate") {
      if (cur?.value && raw && norm(cur.value).includes(norm(raw))) {
        if (field === "specialization") state.flags!.alternatives_to = cur.value;
        delete state.profile[field];
        accepted.push({ field, value: null, op });
      } else if (field === "specialization" && raw) {
        state.flags!.alternatives_to = raw;
        accepted.push({ field, value: null, op });
      } else rejected.push({ field, reason: "negate_without_match" });
      continue;
    }
    if (op === "confirm") {
      if (cur) {
        state.profile[field] = { ...cur, value: raw ?? cur.value, confirmed: true, unsure: false };
        accepted.push({ field, value: state.profile[field]!.value, op });
      } else if (raw) {
        state.profile[field] = { value: raw, confirmed: true, subject: f.subject };
        accepted.push({ field, value: raw, op });
      }
      continue;
    }
    if (!raw) {
      rejected.push({ field, reason: "empty_value" });
      continue;
    }
    let v = raw;
    if (field === "program_level") v = normaliseLevel(raw) ?? raw;
    if (field === "study_mode_preference") v = normaliseMode(raw) ?? raw;
    const entry: ProfileEntry = { value: v, confirmed: op === "correct" || f.confidence === "HIGH", unsure: op === "unsure", subject: f.subject };
    if (field === "academic_score") entry.scale = f.scale ?? "unknown";
    if (field === "academic_score" && scoreToPct(v, entry.scale) === null) entry.unsure = true;
    // A new course resets the specialization and the shown rows (they belonged to the old course).
    if (field === "interested_course" && cur?.value && norm(cur.value) !== norm(v)) {
      delete state.profile.specialization;
      state.flags!.shown_rows = [];
      delete state.flags!.alternatives_to;
    }
    if (field === "specialization") delete state.flags!.alternatives_to;
    state.profile[field] = entry;
    accepted.push({ field, value: v, op });
    if (f.subject && f.subject !== "self" && !state.enquirer) state.enquirer = { name: null, relation: f.subject === "child" ? "parent" : f.subject };
  }
  if (x.enquirer?.relation) state.enquirer = { name: x.enquirer.name ?? null, relation: x.enquirer.relation };
  const intents = (x.intents ?? []).filter((i): i is Intent => typeof i === "string") as Intent[];
  return { state, accepted, rejected, intents, changed: accepted.length > 0 };
}

const ORDINALS: Record<string, number> = { first: 1, "1st": 1, one: 1, pehla: 1, pehli: 1, second: 2, "2nd": 2, two: 2, dusra: 2, doosra: 2, dusri: 2, third: 3, "3rd": 3, three: 3, teesra: 3, teesri: 3 };
function resolveChoice(words: string, shown: number[], state: WittyState): number | null {
  if (!shown.length) return null;
  const t = norm(words);
  const n = t.match(/\b([1-3])\b/)?.[1];
  if (n && shown[Number(n) - 1]) return shown[Number(n) - 1]!;
  // higher ordinals first, so "the second one" is 2, not "one"
  for (const [w, i] of Object.entries(ORDINALS).sort((a, b) => b[1] - a[1])) if (new RegExp(`\\b${w}\\b`).test(t) && shown[i - 1]) return shown[i - 1]!;
  const names = state.flags?.shown_names ?? {};
  for (const id of shown) {
    const first = names[id] ? norm(names[id]!).split(" ")[0]! : "";
    if (first.length >= 3 && t.includes(first)) return id;
  }
  return shown.length === 1 ? shown[0]! : null;
}

/** Row eligibility (counselor input `eligible`: "yes" | "likely (score not known)"); null = not eligible. */
export function rowEligibility(r: CatalogRow, p: Profile): "yes" | "likely (score not known)" | null | "unknown" {
  const rank = qualificationRank(value(p, "highest_qualification"));
  const need = requiredRank(r.min_qualification);
  if (rank === null) return "unknown";
  if (need !== null && rank < need) return null;
  const scoreEntry = p.academic_score;
  const pct = scoreEntry?.value && !scoreEntry.unsure ? scoreToPct(scoreEntry.value, scoreEntry.scale) : null;
  if (pct === null) return "likely (score not known)";
  if (r.min_pct_general && pct < r.min_pct_general) return null;
  return "yes";
}

export function overallEligibility(rows: CatalogRow[], p: Profile, courseFound: boolean): Eligibility {
  if (!courseFound) return "PROGRAM_MISMATCH";
  if (!rows.length) return "INSUFFICIENT_DATA";
  const e = rows.map((r) => rowEligibility(r, p));
  if (e.includes("yes")) return "ELIGIBLE";
  if (e.includes("likely (score not known)")) return "LIKELY_ELIGIBLE";
  if (e.every((x) => x === null)) return "NOT_ELIGIBLE";
  return "INSUFFICIENT_DATA";
}

/** Readiness: timeline "now / this month" or wants_to_apply → READY_NOW; a later date → PLANNING (witty.md §4.4). */
export function readinessOf(p: Profile, intents: Intent[], prev: Readiness = "EXPLORING"): Readiness {
  if (intents.includes("wants_to_apply")) return "READY_NOW";
  return readinessFromTimeline(value(p, "enrollment_timeline")) ?? prev;
}

/**
 * Classification (witty.md §4.4: observed in all 393 conversations): unqualified until name, email and course are known;
 * then eligible + READY_NOW → HOT, eligible + PLANNING → WARM, eligible + a stated "just exploring" timeline → COLD.
 */
export function classify(p: Profile, eligibility: Eligibility, readiness: Readiness, timelineKnown: boolean): Classification {
  if (eligibility === "PROGRAM_MISMATCH") return "PROGRAM_MISMATCH";
  const tier1 = value(p, "student_name") && value(p, "email_id") && value(p, "interested_course");
  if (!tier1 || eligibility !== "ELIGIBLE") return "UNQUALIFIED";
  if (readiness === "READY_NOW") return "HOT";
  if (readiness === "PLANNING") return "WARM";
  return timelineKnown ? "COLD" : "UNQUALIFIED";
}

export function phaseOf(p: Profile, c: Classification, escalated: boolean, support: boolean): Phase {
  if (support) return "SUPPORT";
  if (escalated) return "ESCALATION";
  if (c === "HOT" || c === "WARM" || c === "COLD") return "ENRICH_IT";
  return value(p, "interested_course") ? "QUALIFY_IT" : "EARN_IT";
}

/** The search Witty would run for this profile (w2_search_programs input). */
export function searchQuery(p: Profile, opts: { withoutSpecialization?: boolean } = {}): Record<string, string> | null {
  const course = value(p, "interested_course");
  const field = value(p, "field_of_interest");
  if (!course && !field) return null;
  const q: Record<string, string> = {};
  if (course) q.course = course;
  else if (field) q.field = field;
  const spec = value(p, "specialization");
  if (spec && !opts.withoutSpecialization) q.specialization = spec;
  const level = value(p, "program_level");
  if (level) q.level = level;
  const mode = value(p, "study_mode_preference");
  if (mode) q.mode = mode;
  const uni = value(p, "university_preference");
  if (uni && !/government|best|recommend|any/i.test(uni)) q.university = uni;
  return q;
}

export interface TurnInput {
  state: WittyState;
  accepted: AcceptResult;
  message: string;
  search: SearchResult | null;
  /** search without the specialization, when the student asked for alternatives */
  alternatives?: SearchResult | null;
  knowledge?: Knowledge[];
}

export interface CounselorProgram {
  ref: string;
  has: string[];
  eligible: string;
}

export interface TurnPlan {
  mode: AnswerMode;
  ask: Ask;
  askText: string;
  /** fixed reply (HANDOFF, web stop / erasure); otherwise the counselor writes it */
  fixedReply?: string;
  rows: RefRow[];
  facts: Record<string, unknown>;
  maxWords: number;
  mayPromiseCallback: boolean;
  escalate: boolean;
  eventType: EventType;
  state: WittyState;
  knowledge: Knowledge[];
  /** quick replies the web shows under the reply */
  chips: string[];
  route?: "opt_out";
}

const AFFIRM = /^(yes|yeah|yep|sure|ok(ay)?|haan|han|ha|ji|ji haan|please|bilkul|zaroor|theek hai|thik hai)\b/i;

function bump(s: WittyState, ask: Ask) {
  s.asks ??= {};
  s.asks[ask] = (s.asks[ask] ?? 0) + 1;
}

function pickRows(rows: CatalogRow[], p: Profile, exclude: number[], budget: number | null): { row: CatalogRow; elig: string }[] {
  const scored = rows
    .map((r) => ({ row: r, elig: rowEligibility(r, p) }))
    .filter((x): x is { row: CatalogRow; elig: "yes" | "likely (score not known)" } => x.elig === "yes" || x.elig === "likely (score not known)")
    .filter((x) => !exclude.includes(x.row.id));
  const fee = (r: CatalogRow) => r.fee_total ?? (r.fee_yearly ? r.fee_yearly * 2 : null) ?? Number.MAX_SAFE_INTEGER;
  scored.sort((a, b) => {
    // exact match first (w2 "match"/"uni_match"), then within budget, then lowest fee
    const m = (b.row.match ?? 0) - (a.row.match ?? 0) || Number(!!b.row.uni_match) - Number(!!a.row.uni_match);
    if (m) return m;
    if (budget) {
      const ia = (a.row.fee_yearly ?? fee(a.row)) <= budget ? 0 : 1;
      const ib = (b.row.fee_yearly ?? fee(b.row)) <= budget ? 0 : 1;
      if (ia !== ib) return ia - ib;
    }
    return fee(a.row) - fee(b.row);
  });
  // at most one row per university, so three rows give three choices
  const seen = new Set<string>();
  return scored.filter((x) => (seen.has(x.row.university) ? false : (seen.add(x.row.university), true))).slice(0, 3);
}

/** Decides the turn (modes and asks: counselor MODES + witty.md §4.3–4.5; ask-before-suggest is enforced here). */
export function planTurn(t: TurnInput): TurnPlan {
  const s = cloneState(t.accepted.state);
  const p = s.profile;
  const intents = t.accepted.intents;
  const lang = detectLanguage(t.message, s.language ?? "english");
  s.language = lang;
  s.turn = (s.turn ?? 0) + 1;
  const prevClass = s.classification ?? "UNQUALIFIED";
  const firstName = value(p, "student_name")?.split(" ")[0] ?? null;
  const course = value(p, "interested_course");
  const base = { rows: [] as RefRow[], facts: {} as Record<string, unknown>, maxWords: 80, mayPromiseCallback: false, escalate: false, knowledge: [] as Knowledge[], chips: [] as string[] };

  const finish = (plan: Omit<TurnPlan, "state" | "eventType"> & { eventType?: EventType }): TurnPlan => {
    const rows = t.search?.rows ?? [];
    const courseFound = !course || !t.search || (t.search.visible_total ?? t.search.rows.length) > 0 || (t.search.total_for_course ?? 0) > 0;
    s.eligibility = overallEligibility(rows, p, courseFound);
    s.readiness = readinessOf(p, intents, s.readiness ?? "EXPLORING");
    s.classification = classify(p, s.eligibility, s.readiness, !!value(p, "enrollment_timeline"));
    if (plan.escalate) s.flags!.escalated = true;
    s.phase = phaseOf(p, s.classification, !!s.flags?.escalated, !!s.flags?.supported);
    s.pending_question = plan.ask;
    if (plan.ask !== "NONE") bump(s, plan.ask);
    if (plan.ask === "OFFER_HANDOFF") s.flags!.handoff_offered = true;
    let eventType: EventType = plan.eventType ?? "chat.turn";
    if (!plan.eventType) {
      const classified = ["HOT", "WARM", "COLD"].includes(s.classification);
      if (plan.escalate) eventType = "lead.escalated";
      else if (classified && !s.flags!.qualified_at) eventType = "lead.qualified";
      else if (s.classification !== prevClass) eventType = "classification_changed";
      else if (t.accepted.changed) eventType = "lead.updated";
    }
    if (eventType === "lead.qualified") s.flags!.qualified_at = new Date().toISOString();
    return { ...plan, eventType, state: s };
  };

  // 1. Stop, erasure, support, closing (intents; extractor v6).
  if (intents.includes("erasure_request")) {
    return finish({ ...base, mode: "CLOSE", ask: "NONE", askText: "", fixedReply: erasureText(lang), route: "opt_out", chips: [] });
  }
  if (intents.includes("stop")) {
    s.flags!.opted_out = true;
    return finish({ ...base, mode: "CLOSE", ask: "NONE", askText: "", fixedReply: stopText(lang), route: "opt_out" });
  }
  if (intents.includes("already_enrolled")) {
    s.flags!.supported = true;
    return finish({ ...base, mode: "SUPPORT", ask: "NONE", askText: "" });
  }
  if (intents.includes("closing") && intents.length === 1 && !t.accepted.changed) {
    return finish({ ...base, mode: "CLOSE", ask: "NONE", askText: "" });
  }

  // 2. Hand-off: asks for a human, accepts the offer, or HOT (witty.md §4.5).
  const acceptsOffer = s.pending_question === "OFFER_HANDOFF" && AFFIRM.test(t.message.trim());
  if (!s.flags?.escalated && (intents.includes("asks_human") || acceptsOffer)) {
    return finish({ ...base, mode: "HANDOFF", ask: "NONE", askText: "", fixedReply: handoffText(lang, firstName, course), escalate: true, mayPromiseCallback: true });
  }

  // 3. Course unknown or unsure (EARN_IT).
  if (p.interested_course?.unsure && p.interested_course.value) {
    const ask: Ask = "CONFIRM_COURSE";
    return finish({ ...base, mode: intents.includes("general_question") ? "ANSWER" : "ACK", ask, askText: askText(ask, lang, { course: p.interested_course.value }), knowledge: t.knowledge ?? [] });
  }
  if (!t.search) {
    const ask: Ask = !value(p, "highest_qualification") && (s.asks?.ASK_QUAL_AND_COURSE ?? 0) === 0 && (s.asks?.ASK_COURSE ?? 0) > 0 ? "ASK_QUAL_AND_COURSE" : "ASK_COURSE";
    const mode: AnswerMode = intents.includes("general_question") || intents.includes("asks_eligibility") ? "ANSWER" : "ACK";
    return finish({ ...base, mode, ask, askText: askText(ask, lang), knowledge: mode === "ANSWER" ? (t.knowledge ?? []) : [] });
  }

  // 4. Course not offered (NO_MATCH).
  const visible = t.search.visible_total ?? t.search.rows.length;
  if (visible === 0) {
    return finish({ ...base, mode: "NO_MATCH", ask: "ASK_COURSE", askText: differentCourseText(lang), facts: {} });
  }

  // 5. General question while qualifying: answer from knowledge, then the next ask.
  const nextQualAsk = (): Ask | null => {
    const specs = (t.search?.specializations ?? []).filter(Boolean);
    if (!value(p, "specialization") && !p.specialization?.declined && !s.flags?.alternatives_to && specs.length > 1 && (s.asks?.ASK_SPECIALIZATION ?? 0) < 1 && !intents.includes("asks_programs") && !intents.includes("asks_fees")) return "ASK_SPECIALIZATION";
    const qual = value(p, "highest_qualification");
    const scoreKnown = !!value(p, "academic_score") || p.academic_score?.declined;
    if (!qual && !scoreKnown && (s.asks?.ASK_QUAL_AND_SCORE ?? 0) < 2) return "ASK_QUAL_AND_SCORE";
    if (!qual && (s.asks?.ASK_QUALIFICATION ?? 0) < 2) return "ASK_QUALIFICATION";
    if (qual && !scoreKnown && (s.asks?.ASK_SCORE ?? 0) < 1 && (s.asks?.ASK_QUAL_AND_SCORE ?? 0) < 2) return "ASK_SCORE";
    return null;
  };
  const askVars = { examples: (t.search.specializations ?? []).slice(0, 3).join(", "), qualification: value(p, "highest_qualification") ?? "", course: course ?? "" };
  const qualAsk = nextQualAsk();
  if (intents.includes("general_question") && !intents.includes("asks_programs") && !intents.includes("asks_fees")) {
    const ask = qualAsk ?? afterProgramsAsk(s, intents);
    return finish({ ...base, mode: "ANSWER", ask, askText: askText(ask, lang, askVars), knowledge: t.knowledge ?? [] });
  }

  // 6. Ask before suggesting (DIRECTIONAL: how many options match, no names or fees).
  if (qualAsk) {
    return finish({
      ...base,
      mode: "DIRECTIONAL",
      ask: qualAsk,
      askText: askText(qualAsk, lang, askVars),
      facts: { program_count: visible, specialization_examples: (t.search.specializations ?? []).slice(0, 3) },
    });
  }

  // 7. HOT escalates in the same turn (W1 ENGINE fixture: complete profile, eligible, timeline "now" → lead.escalated).
  if (!s.flags?.escalated) {
    const e = overallEligibility(t.search.rows, p, true);
    const r = readinessOf(p, intents, s.readiness ?? "EXPLORING");
    if (classify(p, e, r, !!value(p, "enrollment_timeline")) === "HOT") {
      return finish({ ...base, mode: "HANDOFF", ask: "NONE", askText: "", fixedReply: handoffText(lang, firstName, course), escalate: true, mayPromiseCallback: true });
    }
  }

  // 8. Eligibility, then programmes.
  const alt = intents.includes("wants_alternatives") && t.alternatives ? t.alternatives : null;
  const pool = alt ? alt.rows.filter((r) => !s.flags?.alternatives_to || r.specialization?.toLowerCase() !== s.flags.alternatives_to.toLowerCase()) : t.search.rows;
  const budget = value(p, "annual_budget") ? budgetToInr(value(p, "annual_budget")!) : null;
  const searchKey = JSON.stringify([searchQuery(p), budget, alt ? "alt" : ""]);
  const relist = searchKey !== s.flags?.last_search_key || intents.some((i) => i === "asks_programs" || i === "asks_fees" || i === "wants_alternatives");
  const eligible = pickRows(pool, p, alt ? (s.flags?.shown_rows ?? []) : [], budget);
  if (!eligible.length) {
    const anyRow = pool.length > 0;
    if (anyRow && pool.every((r) => rowEligibility(r, p) === null)) {
      return finish({ ...base, mode: "NOT_ELIGIBLE", ask: "ASK_COURSE", askText: differentCourseText(lang) });
    }
  }
  if (eligible.length && relist) {
    const rows: RefRow[] = eligible.map((x, i) => ({ ref: `P${i + 1}`, row: x.row }));
    s.flags!.shown_rows = rows.map((r) => r.row.id);
    s.flags!.shown_names = Object.fromEntries(rows.map((r) => [String(r.row.id), r.row.university_short || r.row.university]));
    s.flags!.last_search_key = searchKey;
    const ask = afterProgramsAsk(s, intents);
    const fees = rows.map((r) => r.row.fee_yearly ?? (r.row.fee_total ? r.row.fee_total / 2 : null)).filter((x): x is number => x !== null);
    return finish({
      ...base,
      mode: "PROGRAMS",
      ask,
      askText: askText(ask, lang, askVars),
      rows,
      maxWords: 120,
      facts: {
        program_count: visible,
        requested_specialization_found: t.search.spec_matched ?? true,
        requested_mode_found: t.search.mode_matched ?? true,
        requested_university_found: value(p, "university_preference") ? rows.some((r) => r.row.uni_match) : undefined,
        some_options_above_budget: budget ? fees.some((f) => f > budget) : undefined,
        alternatives_to: alt ? s.flags?.alternatives_to : undefined,
      },
      chips: lang === "english" ? ["Compare these", "Talk to a counsellor"] : ["Compare karo", "Counsellor se baat"],
    });
  }

  // 9. Enrich (programmes already shown): acknowledge and ask the next enrichment question.
  const ask = afterProgramsAsk(s, intents);
  return finish({ ...base, mode: "ACK", ask, askText: askText(ask, lang, askVars) });
}

/** After programmes: timeline → budget (if fees came up) → offer a counsellor once (witty.md §4.3 ask frequencies). */
function afterProgramsAsk(s: WittyState, intents: Intent[]): Ask {
  const p = s.profile;
  if (!value(p, "enrollment_timeline") && !p.enrollment_timeline?.declined && (s.asks?.ASK_TIMELINE ?? 0) < 2) return "ASK_TIMELINE";
  if (!value(p, "annual_budget") && !p.annual_budget?.declined && intents.includes("asks_fees") && (s.asks?.ASK_BUDGET ?? 0) < 1) return "ASK_BUDGET";
  if (!value(p, "primary_motivation") && !p.primary_motivation?.declined && (s.asks?.ASK_MOTIVATION ?? 0) < 1 && (s.asks?.ASK_TIMELINE ?? 0) >= 1) return "ASK_MOTIVATION";
  if (!s.flags?.handoff_offered && !s.flags?.escalated) return "OFFER_HANDOFF";
  return "NONE";
}

/** Counselor input (witty.md §5). */
export function counselorInput(plan: TurnPlan, conversation: { role: "witty" | "student"; text: string }[], studentMessage: string) {
  const profile: Record<string, string> = {};
  for (const [k, e] of Object.entries(plan.state.profile)) if (e?.value && !e.declined && !e.unsure && k !== "email_id") profile[k] = e.value;
  const programs: CounselorProgram[] = plan.rows.map((r) => ({
    ref: r.ref,
    has: hasFields(r.row),
    eligible: rowEligibility(r.row, plan.state.profile) === "yes" ? "yes" : "likely (score not known)",
  }));
  const facts = Object.fromEntries(Object.entries({ ...plan.facts, knowledge: plan.knowledge.length ? plan.knowledge : undefined, writer: plan.state.enquirer ?? undefined }).filter(([, v]) => v !== undefined));
  return {
    task: { answer_mode: plan.mode, ask_text: plan.askText, may_promise_callback: plan.mayPromiseCallback, language: plan.state.language ?? "english", max_words: plan.maxWords },
    profile,
    programs,
    facts,
    conversation: conversation.slice(-6),
    student_message: studentMessage,
  };
}

/**
 * Extractor input (extractor prompt INPUT). The verified email address stays out of it, as it stays out of the
 * counselor input: the model never needs it to read a message (estate audit SITE-17).
 */
export function extractorInput(state: WittyState, studentMessage: string) {
  const known: Record<string, string> = {};
  for (const [k, e] of Object.entries(state.profile)) if (e?.value && k !== "email_id") known[k] = e.value;
  return { pending_question: state.pending_question ?? "NONE", witty_last_message: state.last_witty_message ?? "", known_profile: known, student_message: studentMessage };
}

/** lead_intake `lead` keys, built exactly like w2_crm_payload (witty.md §4.2), for source_system web_agent. */
export function leadPayload(state: WittyState, intents: Intent[], finalRow?: CatalogRow | null): Record<string, unknown> {
  const p = state.profile;
  const score = p.academic_score?.value && !p.academic_score.unsure ? p.academic_score.value : null;
  const budget = value(p, "annual_budget");
  const exp = value(p, "work_experience_years");
  const relation = state.enquirer?.relation;
  const out: Record<string, unknown> = {
    full_name: value(p, "student_name") ?? undefined,
    is_name_confirmed: p.student_name?.confirmed || undefined,
    email: value(p, "email_id") ?? undefined,
    is_email_confirmed: p.email_id?.confirmed || undefined,
    interested_course: value(p, "interested_course") ?? undefined,
    interested_specialization: value(p, "specialization") ?? undefined,
    field_of_interest: value(p, "field_of_interest") ?? undefined,
    university_preference: value(p, "university_preference") ?? undefined,
    interested_university: finalRow?.university ?? undefined,
    programme_level: value(p, "program_level") ?? undefined,
    study_mode_preference: value(p, "study_mode_preference") ?? undefined,
    highest_qualification: value(p, "highest_qualification") ?? undefined,
    current_study: value(p, "current_study") ?? undefined,
    academic_score_raw: score ?? undefined,
    academic_score_pct: score ? (scoreToPct(score, p.academic_score?.scale) ?? undefined) : undefined,
    work_experience_raw: exp ?? undefined,
    work_experience_years_num: exp ? (experienceYears(exp) ?? undefined) : undefined,
    current_job_role: value(p, "current_job_role") ?? undefined,
    annual_budget_raw: budget ?? undefined,
    annual_budget_inr: budget ? (budgetToInr(budget) ?? undefined) : undefined,
    enrollment_timeline: value(p, "enrollment_timeline") ?? undefined,
    primary_motivation: value(p, "primary_motivation") ?? undefined,
    location_raw: value(p, "current_city_country") ?? undefined,
    preferred_language: state.language,
    enquirer_relation: relation ?? undefined,
    guardian_name: relation && /father|mother|parent/.test(relation) ? (state.enquirer?.name ?? undefined) : undefined,
    classification: state.classification,
    classification_ai: state.classification,
    readiness: state.readiness,
    eligibility: state.eligibility,
    conversation_phase: state.phase,
    last_intent: intents.length ? intents.join(",") : undefined,
    is_opted_out: state.flags?.opted_out || undefined,
  };
  return Object.fromEntries(Object.entries(out).filter(([, v]) => v !== undefined && v !== null && v !== ""));
}
