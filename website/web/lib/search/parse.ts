/**
 * Deterministic natural-language parsing for the search box (spec 6.4): budgets, durations, the student's
 * qualification and goals become structured filters, with no LLM call. Programme, specialisation, university and mode
 * words are resolved by the database (web_resolve_query) against the synonym table, so they stay in `rest`.
 */
import type { FinderParams } from "./params";

export interface ParsedQuery {
  rest: string;
  fee_min?: number;
  fee_max?: number;
  duration?: (typeof import("./params").DURATIONS)[number];
  qual?: FinderParams["qual"];
  goal?: string;
  workex?: "required";
}

const NUM = (name: string) => String.raw`(?<${name}>\d+(?:[.,]\d+)*)`;
const CUR = String.raw`(?:₹|rs\.?|inr)?\s*`;
const UNIT = (name: string) => String.raw`\s*(?<${name}>lakhs?|lacs?|lac|l\b|k\b|thousand)?`;

function amount(n: string | undefined, unit: string | undefined): number | undefined {
  if (!n) return undefined;
  const v = Number(n.replace(/,/g, ""));
  if (!Number.isFinite(v)) return undefined;
  const u = (unit ?? "").toLowerCase();
  if (/^(lakhs?|lacs?|lac|l)$/.test(u)) return Math.round(v * 100_000);
  if (u === "k" || u === "thousand") return Math.round(v * 1000);
  return v >= 1000 ? Math.round(v) : undefined; // a bare small number is not a budget
}

function bucket(months: number): ParsedQuery["duration"] {
  if (months <= 12) return "le12";
  if (months <= 24) return "13-24";
  if (months <= 36) return "25-36";
  return "gt36";
}

const GOALS: [RegExp, string][] = [
  [/\b((for )?working professionals?|while working|job ke saath|with (a |my )?job|for working)\b/, "upskill-while-working"],
  [/\b(government jobs?|govt\.? jobs?|sarkari( naukri| job)?|psu jobs?|upsc|ssc)\b/, "government-job-eligibility"],
  [/\b(career (switch|change)|switch(ing)? (my )?career|change (my )?career)\b/, "career-switch"],
  [/\b(promotion|grow in my job|career growth)\b/, "promotion"],
  [/\b(start (a |my )?business|entrepreneur(ship)? goal|own business|family business)\b/, "start-a-business"],
  [/\b(higher stud(y|ies)|further stud(y|ies)|study abroad)\b/, "higher-studies"],
];

const QUALS: [RegExp, NonNullable<FinderParams["qual"]>][] = [
  [/\b(after|completed|passed|pass)\s+(class\s*)?10(th)?\b|\b10th pass\b/, "10th"],
  [/\b(after|completed|passed|pass)\s+(class\s*)?12(th)?\b|\b12th pass\b|\bafter (intermediate|inter|hsc)\b/, "12th"],
  [/\b(after|completed|passed)\s+(a\s+)?diploma\b|\bdiploma holders?\b/, "diploma"],
  [/\b(after|completed)\s+(graduation|my degree|bachelor'?s?|ug)\b|\bfor graduates\b|\bgraduates?\s+can\b/, "graduation"],
  [/\b(after|completed)\s+(post ?graduation|pg|master'?s?)\b/, "postgraduation"],
];

export function parseQuery(input: string): ParsedQuery {
  let s = ` ${input.toLowerCase().replace(/\s+/g, " ")} `;
  const out: ParsedQuery = { rest: "" };
  const cut = (re: RegExp) => {
    s = s.replace(re, " ");
  };

  // budgets: "between 1 and 2 lakh", "under 2 lakh", "above 50k", "1.5 lakh"
  const between = new RegExp(String.raw`\b(?:between|from)\s+${CUR}${NUM("lo")}${UNIT("lu")}\s+(?:and|to|-)\s+${CUR}${NUM("hi")}${UNIT("hu")}`, "i");
  let g = s.match(between)?.groups;
  if (g) {
    const lo = amount(g.lo, g.lu ?? g.hu);
    const hi = amount(g.hi, g.hu ?? g.lu);
    if (lo && hi && lo < hi) {
      out.fee_min = lo;
      out.fee_max = hi;
      cut(between);
    }
  }
  const under = new RegExp(String.raw`\b(?:under|below|less than|upto|up to|within|max(?:imum)?|budget(?: of| is)?|in)\s+${CUR}${NUM("n")}${UNIT("u")}`, "i");
  g = s.match(under)?.groups;
  if (!out.fee_max && g) {
    const v = amount(g.n, g.u);
    if (v) {
      out.fee_max = v;
      cut(under);
    }
  }
  const above = new RegExp(String.raw`\b(?:above|over|more than|min(?:imum)?)\s+${CUR}${NUM("n")}${UNIT("u")}`, "i");
  g = s.match(above)?.groups;
  if (!out.fee_min && g) {
    const v = amount(g.n, g.u);
    if (v) {
      out.fee_min = v;
      cut(above);
    }
  }
  const bare = new RegExp(String.raw`(?:^|\s)${CUR}${NUM("n")}\s*(?<u>lakhs?|lacs?|lac|k)\b`, "i");
  g = s.match(bare)?.groups;
  if (!out.fee_max && g) {
    const v = amount(g.n, g.u);
    if (v) {
      out.fee_max = v;
      cut(bare);
    }
  }

  // work experience before durations ("2 years experience" is not a programme length)
  const exp = /\b(\d+)\+?\s*(years?|yrs?)\s+(of\s+)?(work\s+)?(experience|exp)\b/;
  if (exp.test(s)) {
    out.workex = "required";
    cut(exp);
  }
  const dur = /\b(\d+(?:\.\d+)?)\s*(years?|yrs?|months?)\b/;
  const m = s.match(dur);
  if (m) {
    const months = /^m/.test(m[2]!) ? Number(m[1]) : Number(m[1]) * 12;
    if (months > 0 && months <= 72) {
      out.duration = bucket(months);
      cut(dur);
    }
  }

  for (const [re, q] of QUALS) {
    if (re.test(s)) {
      out.qual = q;
      cut(re);
      break;
    }
  }
  for (const [re, g] of GOALS) {
    if (re.test(s)) {
      out.goal = g;
      cut(re);
      break;
    }
  }
  out.rest = s.replace(/[₹,]/g, " ").replace(/\s+/g, " ").trim();
  return out;
}

/** Applies parsed filters to URL state; explicit URL values win over parsed ones. */
export function mergeParsed(p: FinderParams, parsed: ParsedQuery): FinderParams {
  return {
    ...p,
    q: parsed.rest || undefined,
    fee_min: p.fee_min ?? parsed.fee_min,
    fee_max: p.fee_max ?? parsed.fee_max,
    duration: p.duration.length ? p.duration : parsed.duration ? [parsed.duration] : [],
    qual: p.qual ?? parsed.qual,
    goal: p.goal ?? parsed.goal,
    workex: p.workex ?? parsed.workex,
  };
}
