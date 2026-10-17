import type { ModelProvider } from "./model";
import { env } from "../env";

/**
 * Scripted mock of the two model calls (S-14: no Anthropic key in development and CI). It follows the same JSON
 * contracts as the real prompts, so the whole pipeline (engine, verifier, placeholders, streaming, storage, leads) runs
 * for real; only the language understanding is a handful of patterns. Never used in production.
 */
const COURSES = /\b(mba|bba|bca|mca|b\.?\s?com|m\.?\s?com|b\.?\s?sc|m\.?\s?sc|b\.?\s?tech|m\.?\s?tech|pgdm|b\.?a|m\.?a)\b/i;
const SPECS = ["business analytics", "digital marketing", "human resource", "data science", "cyber security", "international business", "marketing", "finance", "operations", "healthcare", "hr", "ai"];
const WANT = /(want|karna|chahiye|chahta|chahti|interested|looking|options|do an|do a|pursue|find|suggest|show|batao|under)/i;

const zero = { prompt_tokens: 0, cached_tokens: 0, output_tokens: 0, cost_usd: 0 };
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const pretty = (c: string) => {
  const t = c.toUpperCase().replace(/[\s.]/g, "");
  return ({ BCOM: "B.Com", MCOM: "M.Com", BSC: "B.Sc", MSC: "M.Sc", BTECH: "B.Tech", MTECH: "M.Tech", BA: "BA", MA: "MA" } as Record<string, string>)[t] ?? t;
};

type Fact = { field: string; value: string; evidence: string; op: string; subject: string; confidence: string; scale?: string };

export function mockExtract(input: { pending_question: string; known_profile: Record<string, string>; student_message: string }) {
  const m = input.student_message;
  const facts: Fact[] = [];
  const add = (field: string, value: string, evidence: string, extra: Partial<Fact> = {}) =>
    facts.push({ field, value, evidence, op: "set", subject: "self", confidence: "HIGH", ...extra });
  const pending = input.pending_question;

  const course = m.match(COURSES);
  const qualContext = /(done|completed|kiya|pass|graduat|did|have a|hai\b|,\s*\d)/i.test(m) || /QUAL/.test(pending);
  if (course) {
    const wantsCourse = WANT.test(m) || pending === "ASK_COURSE" || (!input.known_profile.interested_course && !qualContext);
    if (wantsCourse && !(qualContext && input.known_profile.interested_course)) {
      add("interested_course", pretty(course[0]), course[0]);
      const pg = /^(m|pgdm)/i.test(course[0]);
      add("program_level", pg ? "PG" : "UG", course[0]);
    } else add("highest_qualification", pretty(course[0]), course[0]);
  } else if (/\b(12th|class 12|graduation|graduate|diploma)\b/i.test(m)) {
    const q = m.match(/\b(12th|class 12|graduation|graduate|diploma)\b/i)![0];
    add("highest_qualification", q, q);
  }
  const score = m.match(/(\d{1,2}(?:\.\d{1,2})?)\s*(%|percent|cgpa)/i) ?? (/SCORE/.test(pending) ? m.match(/\b(\d{1,2}(?:\.\d)?)\b/) : null);
  if (score) add("academic_score", score[1]!, score[0], { scale: /cgpa/i.test(score[0]) ? "cgpa10" : Number(score[1]) <= 10 ? "unknown" : "percent" });
  const spec = SPECS.find((s) => new RegExp(`\\b${s}\\b`, "i").test(m));
  if (spec) {
    const ev = m.match(new RegExp(`\\b${spec}\\b`, "i"))![0];
    if (/(nahi|not|other than|apart from)/i.test(m)) add("specialization", spec, ev, { op: "negate" });
    else add("specialization", spec === "hr" ? "HR" : spec === "ai" ? "AI" : spec.replace(/\b\w/g, (c) => c.toUpperCase()), ev);
  }
  const timeline = m.match(/\b(this month|right now|asap|immediately|this session|next session|next month|next year|in \d+ months|just exploring|isi mahine)\b/i);
  if (timeline) add("enrollment_timeline", timeline[0].toLowerCase(), timeline[0]);
  const budget = m.match(/\b(\d+(?:\.\d+)?\s*(?:k|lakh|l|lac))\b/i);
  if (budget && !score) add("annual_budget", budget[1]!, budget[0]);
  const mode = m.match(/\b(online|distance|odl|regular)\b/i);
  if (mode) add("study_mode_preference", mode[0], mode[0]);

  const intents: string[] = [];
  const has = (re: RegExp) => re.test(m);
  if (has(/\b(options|show|list|suggest|batao|which universit)/i)) intents.push("asks_programs");
  if (has(/\b(fee|fees|cost|price|kitna|kitne|emi)\b/i)) intents.push("asks_fees");
  if (has(/\b(counsell?or|human|call me|talk to|baat karni)\b/i)) intents.push("asks_human");
  if (has(/\b(apply|admission lena|join|enrol)/i)) intents.push("wants_to_apply");
  if (has(/\b(something else|kuch aur|other options|alternatives?)\b/i)) intents.push("wants_alternatives");
  if (has(/\b(delete my data|data delete|remove my data)\b/i)) intents.push("erasure_request");
  if (has(/^\s*stop\s*$/i)) intents.push("stop");
  if (has(/\balready (applied|enrolled)\b/i)) intents.push("already_enrolled");
  if (has(/^\s*(thanks|thank you|ok bye|bye)\b/i) && facts.length === 0) intents.push("closing");
  if (has(/\b(valid|ugc|approved|recogni[sz]ed|what is|kya hai|is it|eligib)/i) && intents.length === 0) intents.push("general_question");
  return { facts, intents };
}

type CounselorInput = {
  task: { answer_mode: string; ask_text: string; language: string };
  programs: { ref: string; has: string[] }[];
  facts: { program_count?: number; requested_specialization_found?: boolean; some_options_above_budget?: boolean; knowledge?: { text: string }[]; alternatives_to?: string };
  profile: Record<string, string>;
};

export function mockReply(i: CounselorInput): string {
  const en = i.task.language === "english";
  const ask = i.task.ask_text;
  const name = i.profile.student_name?.split(" ")[0];
  let body: string;
  switch (i.task.answer_mode) {
    case "DIRECTIONAL":
      body = en
        ? `Good news: we have ${i.facts.program_count} options that could suit you. Your answer helps me show only the ones that fit you.`
        : `Hamare paas ${i.facts.program_count} options hain. Aapke jawab se main sirf wahi dikhaunga jo aapke liye sahi hain.`;
      break;
    case "PROGRAMS": {
      const lines = i.programs.map((p) => `- {{${p.ref}.program}} – {{${p.ref}.university}} ({{${p.ref}.mode}}), ${p.has.includes("fee") ? `{{${p.ref}.fee}}` : "fee on request"}`);
      const notes = [
        i.facts.alternatives_to ? (en ? `These are from other specializations than ${i.facts.alternatives_to}.` : `Yeh ${i.facts.alternatives_to} ke alawa doosri specializations se hain.`) : "",
        i.facts.requested_specialization_found === false ? (en ? "That exact match isn't available; these are the closest." : "Exact match available nahi hai, yeh sabse close options hain.") : "",
        i.facts.some_options_above_budget ? (en ? "Some of these are above your budget." : "Inme se kuch aapke budget se upar hain.") : "",
      ].filter(Boolean);
      body = `${en ? `Here are options you qualify for${name ? `, ${name}` : ""}:` : "Yeh options aapke liye hain:"}\n\n${lines.join("\n")}${notes.length ? `\n\n${notes.join(" ")}` : ""}`;
      break;
    }
    case "NO_MATCH":
      body = en ? "I checked, and we don't currently offer that course, so I don't want to point you to the wrong thing." : "Maine check kiya, yeh course abhi hamare paas nahi hai.";
      break;
    case "NOT_ELIGIBLE":
      body = en
        ? "Going by the qualification and score you shared, you don't meet the minimum requirement for these programmes yet. I can look at other options, or a counsellor can advise."
        : "Aapne jo qualification batayi hai, uske hisaab se abhi aap in programs ki minimum requirement poori nahi karte. Main doosre options dekh sakta hoon, ya ek counsellor aapko sahi raasta bata sakte hain.";
      break;
    case "ANSWER":
      body = i.facts.knowledge?.length
        ? `${i.facts.knowledge[0]!.text} ${en ? "A counsellor can confirm the specifics for you." : "Ek counsellor aapko details confirm kar sakte hain."}`
        : en
          ? "That varies by university and programme, so a counsellor can confirm the specifics for you."
          : "Yeh har university aur program mein alag hota hai, isliye ek counsellor aapko details confirm kar sakte hain.";
      break;
    case "CLOSE":
      body = en ? `You're welcome${name ? `, ${name}` : ""}! Come back any time you want to pick this up again.` : "Aapka swagat hai! Jab chahein wapas aa sakte hain.";
      break;
    case "SUPPORT":
      body = en ? "That's great that you've applied! Your university's student support team is best placed to help with that." : "Aapne apply kar diya hai, yeh achhi baat hai! Aapki university ki student support team sabse sahi madad kar payegi.";
      break;
    default:
      body = en ? `Thanks${name ? `, ${name}` : ""}, noted.` : "Theek hai, note kar liya.";
  }
  return JSON.stringify({ reply: ask ? `${body}\n\n${ask}` : body });
}

export const mockProvider: ModelProvider = {
  name: "mock",
  async extract({ input }) {
    await sleep(60);
    return { text: JSON.stringify(mockExtract(input as Parameters<typeof mockExtract>[0])), usage: zero, model: "mock-witty" };
  },
  async counsel({ input, onText, signal }) {
    const text = mockReply(input as CounselorInput);
    const ttft = env().WEB_ADVISOR_MOCK_TTFT_MS;
    if (ttft) await sleep(ttft);
    for (let i = 0; i < text.length; i += 6) {
      if (signal.aborted) throw new Error("aborted");
      onText(text.slice(i, i + 6));
      await sleep(8);
    }
    return { text, usage: zero, model: "mock-witty" };
  },
};
