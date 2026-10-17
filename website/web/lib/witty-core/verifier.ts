import type { AnswerMode, Knowledge } from "./contract";
import { PLACEHOLDER, unresolved, type RefRow } from "./placeholders";

/**
 * Reply checks mirroring Witty's guardrails (witty.md §4.7, counselor HARD RULES): no unsourced numbers, no university or
 * programme typed by the model, no promises, one question, no meta talk, claims only from knowledge, length cap,
 * placeholders that resolve. Runs on the model's text BEFORE placeholders are filled. Pure.
 */
export interface VerifyInput {
  reply: string;
  mode: AnswerMode;
  askText: string;
  maxWords: number;
  studentMessage: string;
  programCount?: number | null;
  knowledge?: Knowledge[];
  rows: RefRow[];
  /** catalogue university names (and short names) the model must not type */
  universityNames: string[];
  mayPromiseCallback: boolean;
}

const PROMISE = /\b(guarantee[ds]?|assured|100\s*%|definitely get|sure(ly)? get|will get (a |an )?(job|placement|admission|seat|scholarship)|placement guaranteed)\b/i;
const LATER = /\b(i('| wi)ll (check|look into|look at|send|get back|share)|let me (check|look|find)|main (check|dekh) karke)\b/i;
const CALLBACK = /\b((a |our |the )?(counsell?or|advisor|team|someone|we)\s+(will|shall|is going to)\s+(call|contact|reach)|will call you)\b/i;
const META = /\b(json|placeholder|database|the system|tool call|prompt|as an ai language model)\b/i;
const CLAIM = /\b(valid|approved|recogni[sz]ed|accredited|ugc[- ]?(entitled|approved))\b/i;

const words = (s: string) => s.trim().split(/\s+/).filter(Boolean).length;
const numbersIn = (s: string) => [...s.replace(PLACEHOLDER, " ").matchAll(/\d+(?:[.,]\d+)*/g)].map((m) => m[0]!.replace(/,/g, ""));

export function verifyReply(v: VerifyInput): string[] {
  const errors: string[] = [];
  const text = v.reply.trim();
  if (!text) return ["empty"];
  if (words(text) > Math.ceil(v.maxWords * 1.25)) errors.push("too_long");

  const bare = text.replace(PLACEHOLDER, " ");
  const questions = (bare.match(/\?/g) ?? []).length;
  const askQuestions = (v.askText.match(/\?/g) ?? []).length;
  if (!v.askText && questions > 0 && v.mode !== "ANSWER") errors.push("asked_without_ask");
  if (questions > Math.max(1, askQuestions)) errors.push("multiple_questions");

  const allowed = new Set<string>([
    ...numbersIn(v.studentMessage),
    ...numbersIn(v.askText),
    ...(v.knowledge ?? []).flatMap((k) => numbersIn(k.text)),
    ...(v.programCount != null ? [String(v.programCount)] : []),
  ]);
  for (const n of numbersIn(bare)) {
    const small = Number(n) <= 10 && !n.includes(".");
    if (!allowed.has(n) && !small) {
      errors.push("unsourced_number");
      break;
    }
  }

  const lower = bare.toLowerCase();
  if (v.universityNames.some((u) => u.length >= 4 && new RegExp(`\\b${u.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`).test(lower)))
    errors.push("typed_university");
  if (/₹|\brs\.?\s?\d|\binr\b|lakh|\d+\s?k\b/i.test(bare) && !/₹|lakh|\dk\b/i.test(v.studentMessage)) errors.push("typed_fee");
  if (PROMISE.test(bare)) errors.push("promise");
  if (LATER.test(bare)) errors.push("promise_later");
  if (!v.mayPromiseCallback && CALLBACK.test(bare)) errors.push("callback_promise");
  if (META.test(bare)) errors.push("meta_talk");
  const kb = (v.knowledge ?? []).map((k) => k.text).join(" ");
  if (CLAIM.test(bare) && !CLAIM.test(kb) && !CLAIM.test(v.askText)) errors.push("unsourced_claim");
  if (unresolved(text, v.rows).length) errors.push("bad_placeholder");
  if ((v.mode === "PROGRAMS" || v.mode === "NO_MATCH") && v.rows.length && !PLACEHOLDER.test(text)) errors.push("programs_without_rows");
  PLACEHOLDER.lastIndex = 0;
  if (!["PROGRAMS", "NO_MATCH"].includes(v.mode) && PLACEHOLDER.test(text)) errors.push("rows_in_wrong_mode");
  PLACEHOLDER.lastIndex = 0;
  return [...new Set(errors)];
}

/** Safe deterministic reply used when the model's reply fails twice (Witty's "fixed fallback text"). */
export function fallbackReply(mode: AnswerMode, askText: string, rows: RefRow[], lang: "english" | "hinglish" | "hindi"): string {
  const lead =
    mode === "PROGRAMS" || mode === "NO_MATCH"
      ? lang === "english"
        ? "Here are options that match what you told me:"
        : "Yeh options aapki batayi details se match karte hain:"
      : lang === "english"
        ? "Thanks, noted."
        : "Theek hai, note kar liya.";
  const list = mode === "PROGRAMS" || mode === "NO_MATCH" ? rows.map((r) => `- {{${r.ref}.program}} – {{${r.ref}.university}} ({{${r.ref}.mode}})${r.row.fee_yearly || r.row.fee_semester || r.row.fee_total ? `, {{${r.ref}.fee}}` : ", fee on request"}`).join("\n") : "";
  return [lead, list, askText].filter(Boolean).join("\n\n");
}
