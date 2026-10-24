import type { ModelAnswer, ModelClient, ModelRequest } from "../client.ts";
import type { AiDb, CallRecord, Claim } from "../db.ts";
import type { AiSettings, Provider, Tier } from "../models.ts";
import { PROMPTS } from "../prompts.generated.ts";
import { runTask } from "../worker.ts";
import { INCIDENTS, PLANTED, QUESTIONS, type EvalIncident, type EvalQuestion } from "./fixtures.ts";

// Runs the eval set through the real worker (routing, masking, budget checks, schema validation) with a fake database,
// on one tier, and grades the filed answers deterministically. The model client is either a real one (npm run ai:eval)
// or the reference client below, which answers from the expectations: that run proves the plumbing, the grading and
// the mask, and judges no model.

export type ItemScore = {
  id: string;
  kind: "classify" | "triage" | "ask";
  filed: boolean;
  score: number;
  checks: Record<string, boolean>;
  error?: string;
  costUsd: number;
  costInr: number;
  latencyMs: number;
  model?: string;
  leaks: string[];
};

export type TierReport = { tier: Tier; provider: Provider; items: ItemScore[] };

const BASE_AT = Date.parse("2026-10-24T06:00:00Z");

/** The context the database would build for an eval incident (one.ai_incident_context), before the worker's mask. */
export function incidentContext(e: EvalIncident, n: number) {
  const opened = new Date(BASE_AT - e.minutesOpen * 60_000).toISOString();
  return {
    incident: {
      id: n,
      check_id: e.check.id,
      app: e.check.app,
      severity: e.check.severity,
      title: e.check.title,
      opened_at: opened,
      last_seen_at: new Date(BASE_AT).toISOString(),
      occurrences: Math.max(1, Math.round(e.minutesOpen / 5)),
      reopened_count: 0,
      acknowledged: false,
      resolved_at: null,
      resolution: null,
      subjects: e.subjects ?? [],
      tags: [],
      alert_state: e.check.severity === "P1" ? "sent" : "digest",
      evidence: { status: "fail", value: e.value },
      first_evidence: { status: "fail", value: e.value },
      summary: null,
      root_cause: null,
      parent_id: null,
      minutes_open: e.minutesOpen,
    },
    check: { ...e.check, cadence_s: 60, tags: [], auto_fix_id: null, open_after: 1, resolve_after: 3, rule_sql: null },
    recent_results: [0, 1, 2].map((k) => ({
      at: new Date(BASE_AT - k * 60_000).toISOString(),
      status: "fail",
      value: e.value,
      error: null,
      ms: 40,
    })),
    history: [],
    open_same_app: (e.openSameApp ?? []).map((o, k) => ({ id: 900 + k, severity: "P2", opened_at: opened, ...o })),
    children: [],
    heartbeats_down: (e.heartbeatsDown ?? []).map((c) => ({
      component: c,
      last_ok_at: opened,
      last_error_at: opened,
      last_error: "no answer",
    })),
    fixes_run: [],
    ai_notes: [],
  };
}

function claimFor(kind: "classify" | "triage" | "ask", tier: Tier, ai: AiSettings, n: number, context: unknown): Claim {
  return {
    task: { id: n, kind, input: {}, model_hint: tier, attempts: 1, incident_id: kind === "ask" ? null : n },
    ai,
    budget: { spent_inr: 0, cap_inr: ai.daily_cap_inr, remaining_inr: ai.daily_cap_inr },
    context,
  };
}

type Verdict = { result?: Record<string, unknown>; error?: string; calls: CallRecord[] };

class EvalDb implements AiDb {
  verdict: Verdict = { calls: [] };
  private readonly tools: Record<string, unknown>;

  constructor(tools: Record<string, unknown> = {}) {
    this.tools = tools;
  }
  async claim() {
    return null;
  }
  async finish(_t: number, _h: string, result: Record<string, unknown>, calls: CallRecord[]) {
    this.verdict = { result, calls };
  }
  async fail(_t: number, _h: string, error: string, calls: CallRecord[]) {
    this.verdict = { error, calls };
    return "failed";
  }
  async defer(_t: number, _h: string, reason: string) {
    this.verdict = { error: `deferred: ${reason}`, calls: [] };
  }
  async tool(_t: number, _h: string, name: string) {
    return name in this.tools ? { ok: true, data: this.tools[name] } : { ok: true, data: [] };
  }
  async aiSettings() {
    return null;
  }
}

/** Every text a model was sent or wrote, for the leak check. */
class Recorder implements ModelClient {
  readonly provider: Provider;
  readonly texts: string[] = [];
  private readonly inner: ModelClient;

  constructor(inner: ModelClient) {
    this.inner = inner;
    this.provider = inner.provider;
  }
  async complete(req: ModelRequest): Promise<ModelAnswer> {
    this.texts.push(req.system, req.user);
    const a = await this.inner.complete(req);
    this.texts.push(a.text);
    return a;
  }
  check(model: string) {
    return this.inner.check(model);
  }
}

const lower = (s: string) => s.toLowerCase();
const digitsOnly = (s: string) => s.replace(/\D/g, "");

export function leaksIn(texts: string[]): string[] {
  const all = texts.join("\n");
  const allDigits = digitsOnly(all);
  return PLANTED.filter((p) => (/^\d+$/.test(p) ? allDigits.includes(p) : lower(all).includes(lower(p))));
}

const hits = (text: string, groups: string[][]) => groups.map((g) => g.some((alt) => lower(text).includes(lower(alt))));
const fraction = (bs: boolean[]) => (bs.length ? bs.filter(Boolean).length / bs.length : 1);

function cost(calls: CallRecord[]) {
  return {
    costUsd: calls.reduce((n, c) => n + (c.cost_usd ?? 0), 0),
    costInr: calls.reduce((n, c) => n + (c.cost_inr ?? 0), 0),
    latencyMs: calls.reduce((n, c) => n + (c.latency_ms ?? 0), 0),
    model: calls.at(-1)?.model,
  };
}

async function runOne(
  kind: "classify" | "triage" | "ask",
  claim: Claim,
  client: ModelClient,
  tools?: Record<string, unknown>,
) {
  const db = new EvalDb(tools);
  const rec = new Recorder(client);
  await runTask(claim, {
    db,
    clientFor: (p) => (p === client.provider ? rec : null),
    holder: "eval",
    deadline: Date.now() + 600_000,
  });
  return { verdict: db.verdict, leaks: leaksIn(rec.texts), kind };
}

export function scoreIncident(e: EvalIncident, kind: "classify" | "triage", v: Verdict, leaks: string[]): ItemScore {
  const r = v.result ?? {};
  const checks: Record<string, boolean> = { filed: Boolean(v.result), masked: leaks.length === 0 };
  if (kind === "classify") {
    checks.category = e.expect.category.includes(String(r.category));
    if (e.expect.codeRelated !== undefined) checks.code_related = r.code_related === e.expect.codeRelated;
  } else {
    const text = [r.summary, r.likely_cause, ...(Array.isArray(r.next_steps) ? r.next_steps : [])]
      .map(String)
      .join(" ");
    hits(text, e.expect.mentions).forEach((b, k) => (checks[`fact_${k + 1}`] = b));
    if (e.expect.proposeFix !== undefined) checks.propose_fix = r.propose_fix === e.expect.proposeFix;
  }
  const graded = Object.entries(checks).filter(([k]) => k !== "filed" && k !== "masked");
  return {
    id: e.id,
    kind,
    filed: checks.filed ?? false,
    score: v.result ? fraction(graded.map(([, b]) => b)) : 0,
    checks,
    ...(v.error ? { error: v.error } : {}),
    ...cost(v.calls),
    leaks,
  };
}

export function scoreQuestion(q: EvalQuestion, v: Verdict, leaks: string[]): ItemScore {
  const r = v.result ?? {};
  const answer = String(r.answer ?? "");
  const used = Array.isArray(r.queries) ? (r.queries as Array<{ tool?: string }>).map((x) => x.tool) : [];
  const checks: Record<string, boolean> = { filed: Boolean(v.result), masked: leaks.length === 0 };
  hits(answer, q.expect.mentions).forEach((b, k) => (checks[`fact_${k + 1}`] = b));
  if (q.expect.toolsAny.length) checks.tools = used.some((t) => t !== undefined && q.expect.toolsAny.includes(t));
  if (q.expect.noDigits) checks.no_phone = !/\d{7,}/.test(answer.replace(/[\s().-]/g, ""));
  const graded = Object.entries(checks).filter(([k]) => k !== "filed" && k !== "masked");
  return {
    id: q.id,
    kind: "ask",
    filed: checks.filed ?? false,
    score: v.result ? fraction(graded.map(([, b]) => b)) : 0,
    checks,
    ...(v.error ? { error: v.error } : {}),
    ...cost(v.calls),
    leaks,
  };
}

/** The whole set on one tier: classify and triage for each incident, then each question. */
export async function runEval(
  ai: AiSettings,
  tier: Tier,
  client: ModelClient,
  onItem?: (s: ItemScore) => void,
): Promise<TierReport> {
  const items: ItemScore[] = [];
  const push = (s: ItemScore) => {
    items.push(s);
    onItem?.(s);
  };
  for (const [k, e] of INCIDENTS.entries()) {
    const ctx = incidentContext(e, k + 1);
    for (const kind of ["classify", "triage"] as const) {
      const { verdict, leaks } = await runOne(kind, claimFor(kind, tier, ai, k + 1, ctx), client);
      push(scoreIncident(e, kind, verdict, leaks));
    }
  }
  for (const [k, q] of QUESTIONS.entries()) {
    const ctx = { question: q.question, today_ist: "2026-10-24" };
    const { verdict, leaks } = await runOne("ask", claimFor("ask", tier, ai, 100 + k, ctx), client, q.tools);
    push(scoreQuestion(q, verdict, leaks));
  }
  return { tier, provider: client.provider, items };
}

export type TierSummary = {
  tier: Tier;
  provider: Provider;
  model: string;
  items: number;
  filed: number;
  classify: number;
  triage: number;
  ask: number;
  overall: number;
  leaks: number;
  costUsd: number;
  costInr: number;
  p50LatencyMs: number;
};

const mean = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0);

export function summarise(r: TierReport): TierSummary {
  const of = (kind: ItemScore["kind"]) => r.items.filter((i) => i.kind === kind).map((i) => i.score);
  const lat = r.items.map((i) => i.latencyMs).sort((a, b) => a - b);
  return {
    tier: r.tier,
    provider: r.provider,
    model: r.items.find((i) => i.model)?.model ?? "?",
    items: r.items.length,
    filed: r.items.filter((i) => i.filed).length,
    classify: mean(of("classify")),
    triage: mean(of("triage")),
    ask: mean(of("ask")),
    overall: mean(r.items.map((i) => i.score)),
    leaks: r.items.reduce((n, i) => n + i.leaks.length, 0),
    costUsd: Math.round(r.items.reduce((n, i) => n + i.costUsd, 0) * 1e4) / 1e4,
    costInr: Math.round(r.items.reduce((n, i) => n + i.costInr, 0) * 100) / 100,
    p50LatencyMs: lat[Math.floor(lat.length / 2)] ?? 0,
  };
}

/**
 * The reference client: answers each task from the eval's own expectations, as a perfect model would. Used offline
 * (no key) to prove the harness: if it does not score 100% with no leak, the eval or the worker is wrong.
 */
export class ReferenceClient implements ModelClient {
  readonly provider: Provider;

  constructor(provider: Provider) {
    this.provider = provider;
  }

  async complete(req: ModelRequest): Promise<ModelAnswer> {
    const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
    const answer = (json: unknown): ModelAnswer => ({
      text: JSON.stringify(json),
      model: req.model,
      usage,
      stop: "end",
      latencyMs: 0,
    });
    if (req.system.endsWith(PROMPTS.ask.text)) {
      const q = QUESTIONS.find((x) => req.user.includes(x.question.slice(0, 40)));
      if (!q) return answer({ calls: [], answer: "unknown" });
      const say = q.expect.mentions.map((g) => g[0]).join(", ");
      if (req.user.includes("No tools have been called yet.")) {
        const tools = q.expect.toolsAny.length ? q.expect.toolsAny : Object.keys(q.tools);
        return answer({
          calls: tools.map((t) => ({ tool: t, args_json: t === "incident" ? '{"id": 12}' : "{}" })),
          answer: null,
        });
      }
      return answer(req.user.includes("last round") ? { answer: say } : { calls: [], answer: say });
    }
    const n = Number(/Incident #(\d+)\./.exec(req.user)?.[1] ?? 0);
    const e = INCIDENTS[n - 1];
    if (!e) return answer({});
    if (req.system.endsWith(PROMPTS.classify.text)) {
      return answer({
        category: e.expect.category[0],
        code_related: e.expect.codeRelated ?? false,
        confidence: "high",
        note: "reference",
      });
    }
    return answer({
      summary: `${e.check.id}: ${e.expect.mentions.map((g) => g[0]).join(", ")}.`,
      likely_cause: null,
      next_steps: [],
      checks_to_watch: [],
      confidence: "high",
      propose_fix: e.expect.proposeFix ?? false,
    });
  }

  async check() {
    return { ok: true, detail: "reference" };
  }
}
