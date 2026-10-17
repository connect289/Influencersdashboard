import "server-only";
import {
  ENGINE_VERSION,
  acceptFacts,
  counselorInput,
  extractorInput,
  fallbackReply,
  fillPlaceholders,
  leadPayload,
  planTurn,
  searchQuery,
  verifyReply,
  type Extraction,
  type Knowledge,
  type SearchResult,
  type WittyState,
} from "@/lib/witty-core";
import type { Settings } from "@/lib/settings";
import { PlaceholderFilter, ReplyDecoder, parseJson, parseReply } from "@/lib/web-advisor/stream";
import type { WittyEvent } from "@/lib/web-advisor/events";
import { rpc } from "../db";
import { isProduction } from "../env";
import { errorFields, log } from "../log";
import { offeringCards } from "../search";
import type { Student } from "../student-session";
import { recordFailure, recordSuccess } from "./breaker";
import { modelProvider, type ModelUsage } from "./model";
import { corePrompts } from "./prompts";

/**
 * One web_advisor turn (docs/AGENT_ARCHITECTURE.md §3.7): extractor → engine (search, knowledge, eligibility, mode) →
 * counselor (streamed, placeholders filled as they close) → verifier (one rewrite, then a safe fallback) → commit
 * (transcript, state, usage, lead via lead_intake). Programme cards stream before the prose.
 */
export interface SessionRow {
  session: { id: string; turns: number; prompt_tokens: number; output_tokens: number };
  state: WittyState;
  phone: string | null;
  messages: { id: number; direction: "in" | "out"; content: string; answer_mode: string | null; meta: Record<string, unknown> | null; created_at: string; rating: number | null }[];
}

export async function openSession(student: Student, fresh = false): Promise<SessionRow | null> {
  return rpc<SessionRow | null>("web_advisor_session_open", { p_student: student.studentId, p_new: fresh, p_is_test: !isProduction() });
}

const add = (a: ModelUsage, b: ModelUsage): ModelUsage => ({
  prompt_tokens: a.prompt_tokens + b.prompt_tokens,
  cached_tokens: a.cached_tokens + b.cached_tokens,
  output_tokens: a.output_tokens + b.output_tokens,
  cost_usd: Math.round((a.cost_usd + b.cost_usd) * 1e5) / 1e5,
});
const ZERO: ModelUsage = { prompt_tokens: 0, cached_tokens: 0, output_tokens: 0, cost_usd: 0 };

/** Quick replies: answers to the pending question first, then the plan's own (compare, counsellor); at most five. */
function chipsFor(ask: string, search: SearchResult | null, base: string[]): string[] {
  return [...new Set([...askChips(ask, search), ...base])].slice(0, 5);
}
function askChips(ask: string, search: SearchResult | null): string[] {
  switch (ask) {
    case "ASK_SPECIALIZATION":
      return [...(search?.specializations ?? []).slice(0, 3), "Not sure yet"];
    case "ASK_TIMELINE":
      return ["This session", "Next session", "Just exploring"];
    case "OFFER_HANDOFF":
      return ["Yes, please", "Not now"];
    case "ASK_COURSE":
    case "ASK_QUAL_AND_COURSE":
      return ["Online MBA", "BBA", "BCA", "MCA"];
    default:
      return [];
  }
}

export async function runTurn(o: {
  student: Student;
  session: SessionRow;
  message: string;
  messageId: string;
  settings: Settings;
  emit: (e: WittyEvent) => void;
  signal: AbortSignal;
}): Promise<void> {
  const t0 = Date.now();
  const { settings, emit, signal, message } = o;
  const budget = settings.web_advisor_budget;
  const models = settings.web_advisor_models;
  const provider = modelProvider();
  const runId = crypto.randomUUID();
  emit({ type: "thinking" });

  const commit = async (p: Record<string, unknown>) =>
    rpc<{ ok: boolean; out_id?: number; status?: string }>("web_advisor_turn_commit", {
      p: { session_id: o.session.session.id, student_id: o.student.studentId, message_id: o.messageId, run_id: runId, student_message: message, ...p },
    });

  // Per-session budget (spec 3A): no model call beyond it; offer a counsellor instead.
  const used = o.session.session.prompt_tokens + o.session.session.output_tokens;
  if (used > budget.max_tokens_per_session || o.session.session.turns >= budget.max_turns_per_session) {
    const reply = "We've covered a lot together. A counsellor can take it from here and answer everything in detail.";
    emit({ type: "token", text: reply });
    const r = await commit({ reply, answer_mode: "CLOSE", reply_source: "budget", model: "none", latency_ms: Date.now() - t0, meta: { budget: true } });
    emit({ type: "done", messageId: r.out_id ?? null, chips: ["Talk to a counsellor"], mode: "CLOSE" });
    return;
  }

  const prompts = await corePrompts(ENGINE_VERSION);
  if (!prompts) throw new Error("prompts unavailable");
  const state: WittyState = o.session.state?.profile ? o.session.state : { profile: {} };
  const conversation = o.session.messages.slice(-6).map((m) => ({ role: m.direction === "in" ? ("student" as const) : ("witty" as const), text: m.content }));
  let usage = ZERO;
  const verifyErrors: string[] = [];

  // 1. Extractor (JSON). A failure degrades to "no facts" rather than breaking the turn.
  let extraction: Extraction = { facts: [], intents: [] };
  const tx = Date.now();
  try {
    const r = await provider.extract({ model: models.extractor, system: prompts.extractor, input: extractorInput(state, message), signal });
    usage = add(usage, r.usage);
    const j = parseJson(r.text) as Partial<Extraction> | null;
    if (j && Array.isArray(j.facts)) extraction = { facts: j.facts, intents: Array.isArray(j.intents) ? j.intents : [], enquirer: j.enquirer ?? null };
    else verifyErrors.push("extractor_unparsable");
  } catch (err) {
    if (signal.aborted) throw err;
    verifyErrors.push("extractor_failed");
    log("warn", "web_advisor.extractor_failed", errorFields(err));
  }
  const extractorMs = Date.now() - tx;

  // 2. Engine: facts, search (Witty's own catalogue function, website-visible rows), knowledge, decision.
  const accepted = acceptFacts(state, extraction, message);
  const q = searchQuery(accepted.state.profile);
  const ts = Date.now();
  const search = q ? await rpc<SearchResult>("web_advisor_search", { q }) : null;
  const alternatives =
    q && accepted.intents.includes("wants_alternatives") ? await rpc<SearchResult>("web_advisor_search", { q: searchQuery(accepted.state.profile, { withoutSpecialization: true }) }) : null;
  const knowledge = accepted.intents.some((i) => i === "general_question" || i === "asks_eligibility" || i === "pay_after_placement")
    ? await rpc<Knowledge[]>("web_advisor_kb", { p_text: message, p_limit: 3 })
    : [];
  const searchMs = Date.now() - ts;
  const plan = planTurn({ state: accepted.state, accepted, message, search, alternatives, knowledge });

  // 3. Cards first (deterministic), so the student sees results before the prose.
  if (plan.rows.length) {
    const cards = await offeringCards(plan.rows.map((r) => r.row.id)).catch(() => []);
    const byId = new Map(cards.map((c) => [c.id, c]));
    const ordered = plan.rows.map((r) => byId.get(r.row.id)).filter((c): c is NonNullable<typeof c> => !!c);
    if (ordered.length) emit({ type: "cards", items: ordered });
  }

  // 4. Reply.
  let ttft = 0;
  let finalRaw: string;
  let source = "llm";
  let modelName: string = provider.name === "mock" ? "mock-witty" : models.counselor;
  const universityNames = [
    ...new Set([
      ...(search?.universities ?? []).flatMap((u) => [u.name, u.short_name ?? ""]),
      ...(search?.rows ?? []).flatMap((r) => [r.university, r.university_short ?? ""]),
    ]),
  ].filter((n) => n && n.length >= 4);
  const fill = (raw: string) => fillPlaceholders(raw, plan.rows);

  if (plan.fixedReply) {
    finalRaw = plan.fixedReply;
    source = "fixed";
    modelName = "fixed";
    ttft = Date.now() - t0;
    emit({ type: "token", text: finalRaw });
  } else {
    const input = counselorInput(plan, conversation, message);
    const decoder = new ReplyDecoder();
    const filter = new PlaceholderFilter((p) => fill(p));
    let streamed = "";
    const r = await provider.counsel({
      model: models.counselor,
      system: prompts.counselor,
      input,
      signal,
      onText: (d) => {
        const text = filter.feed(decoder.feed(d));
        if (text) {
          if (!ttft) ttft = Date.now() - t0;
          streamed += text;
          emit({ type: "token", text });
        }
      },
    });
    usage = add(usage, r.usage);
    const tail = filter.flush();
    if (tail) {
      streamed += tail;
      emit({ type: "token", text: tail });
    }
    let reply = parseReply(r.text) ?? "";
    // Witty's verifier, plus one web-only rule: links reach a reply only through brochure placeholders filled from the
    // catalogue, so a literal URL written by the model is rejected (rewrite, then the safe fallback).
    const check = (text: string) => [
      ...verifyReply({
        reply: text,
        mode: plan.mode,
        askText: plan.askText,
        maxWords: plan.maxWords,
        studentMessage: message,
        programCount: (plan.facts.program_count as number | undefined) ?? null,
        knowledge: plan.knowledge,
        rows: plan.rows,
        universityNames,
        mayPromiseCallback: plan.mayPromiseCallback,
      }),
      ...(/\bhttps?:\/\/|\bwww\./i.test(text) ? ["raw_url"] : []),
    ];
    let errors = check(reply);
    if (errors.length) {
      verifyErrors.push(...errors);
      // One rewrite with the problems named (Witty's VERIFIER), then a safe deterministic fallback.
      try {
        const rw = await provider.counsel({
          model: models.counselor,
          system: prompts.counselor,
          input: { ...input, rewrite: { previous_reply: reply, problems: errors } },
          signal,
          onText: () => undefined,
        });
        usage = add(usage, rw.usage);
        reply = parseReply(rw.text) ?? "";
        errors = check(reply);
        source = "rewrite";
      } catch (err) {
        if (signal.aborted) throw err;
        errors = ["rewrite_failed"];
      }
      if (errors.length) {
        verifyErrors.push(...errors.map((e) => `rewrite:${e}`));
        reply = fallbackReply(plan.mode, plan.askText, plan.rows, plan.state.language ?? "english");
        source = "fallback";
      }
    }
    finalRaw = reply;
    if (fill(finalRaw) !== streamed) emit({ type: "replace", text: fill(finalRaw) });
  }

  const finalText = fill(finalRaw);
  plan.state.last_witty_message = finalText;
  const finalRow = plan.state.flags?.final_program_id ? (search?.rows.find((r) => r.id === plan.state.flags!.final_program_id) ?? null) : null;
  const chips = chipsFor(plan.ask, search, plan.chips);
  const r = await commit({
    reply: finalText,
    answer_mode: plan.mode,
    reply_source: source,
    model: modelName,
    usage,
    latency_ms: Date.now() - t0,
    verify_errors: verifyErrors.length ? verifyErrors : null,
    state: plan.state,
    classification: plan.state.classification,
    readiness: plan.state.readiness,
    eligibility: plan.state.eligibility,
    phase: plan.state.phase,
    language: plan.state.language,
    escalate: plan.escalate,
    event_type: plan.eventType,
    lead: leadPayload(plan.state, accepted.intents, finalRow),
    agent_core_version: prompts.version,
    meta: {
      provider: provider.name,
      ask: plan.ask,
      intents: accepted.intents,
      rows: plan.rows.map((x) => x.row.id),
      chips,
      route: plan.route ?? null,
      knowledge: plan.knowledge.map((k) => k.ref),
      facts_accepted: accepted.accepted.map((a) => a.field),
      facts_rejected: accepted.rejected,
      ttft_ms: ttft,
      extractor_ms: extractorMs,
      search_ms: searchMs,
    },
  });
  await recordSuccess();
  log("info", "web_advisor.turn", { mode: plan.mode, ask: plan.ask, source, ttft_ms: ttft, total_ms: Date.now() - t0, tokens: usage.prompt_tokens + usage.output_tokens, provider: provider.name });
  emit({ type: "done", messageId: r.out_id ?? null, chips, mode: plan.mode, route: plan.route, handoff: plan.escalate });
}

export async function failTurn(reason: string) {
  await recordFailure(reason);
}
