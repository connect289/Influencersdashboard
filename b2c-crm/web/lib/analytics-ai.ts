import "server-only";
import { z } from "zod";
import { AiUnavailable, callClaude } from "@/lib/ai";
import { istDate, SpecSchema, VIZ, type Catalog, type Result, type Spec, type Viz } from "@/lib/analytics";
import { containsPii, scrubPii } from "@/lib/scrub";
import { adminClient } from "@/lib/supabase/admin";

/**
 * Claude in analytics (spec B13.4) and on the lead (B8.3). What goes to the model:
 * - Ask: the question and the caller's metric and dimension catalogue (labels and keys only), never data.
 * - Explain and insights: aggregated rows (counts and sums by day, source, counsellor, university), never a lead.
 * - Brief: b2c.brief_input (profile fields with the first name only, interest, stage, partner history, Witty turns and
 *   recent activity), scrubbed of phone numbers and emails in the database and again here.
 * The spec Claude writes is run by b2c.analytics_run as the asking person, so the database applies their scope.
 */

// ---------- Ask ----------
const AskOut = z.object({
  answerable: z.boolean(),
  reason: z.string().describe("If not answerable: one short sentence saying what is missing. Otherwise empty."),
  title: z.string(),
  viz: z.enum(VIZ),
  spec: z.object({
    metrics: z.array(z.string()),
    dims: z.array(z.string()),
    filters: z.array(z.object({ dim: z.string(), op: z.enum(["eq", "neq", "in", "not_in", "contains", "is_null", "not_null"]), value: z.array(z.string()) })),
    from: z.string(),
    to: z.string(),
    compare: z.enum(["none", "previous", "year"]),
  }),
});

const ASK_SYSTEM = `You turn a question about Eduwit's B2C sales and nurture CRM into a query spec. You never see data; the database runs the spec for the person asking and limits it to what their role may see.
Rules:
- Use only metric and dimension keys from the catalogue in the message. At most 6 metrics and 2 dimensions.
- Filters compare a dimension's text value: eq/neq take one value in the array, in/not_in take several, contains takes one, is_null/not_null take none. Use the people's names as written in the question for the counsellor dimension.
- Dates are IST calendar days (YYYY-MM-DD), inclusive. Default to the last 30 days when the question gives no period. "This month" starts on the 1st.
- For "compare", "grew", "fell" or "change" questions set compare to previous (or year for year-on-year) and pick a viz that shows it.
- Pick viz: kpi for one number, line for a metric over days or weeks (dimension day/week/month), bar for a metric by one category, stacked for two dimensions, funnel for funnel metrics in order, table for several metrics by a category.
- If the catalogue cannot answer the question, set answerable to false and say why in one sentence.`;

export type AskAnswer = { title: string; viz: Viz; spec: Spec; result: Result; logId: number | null };

export async function askQuestion(opts: { question: string; catalog: Catalog; userId: string; run: (spec: Spec) => Promise<Result> }): Promise<AskAnswer> {
  const q = scrubPii(opts.question.trim()).slice(0, 500);
  if (q.length < 4) throw new AiUnavailable("Ask a question about your numbers.");
  const cat = {
    metrics: opts.catalog.metrics.map((m) => ({ key: m.key, label: m.label, area: m.area, as_of_now: m.as_of_now, ...(m.description ? { about: m.description } : {}) })),
    dims: opts.catalog.dims.map((d) => ({ key: d.key, label: d.label, ...(d.sources ? { only_for_sources: d.sources } : {}) })),
  };
  let feedback = "";
  for (let attempt = 0; attempt < 2; attempt++) {
    const { output, logId } = await callClaude({
      purpose: "ask", schema: AskOut, system: ASK_SYSTEM, userId: opts.userId, question: q, maxTokens: 2000,
      user: `Today (IST): ${istDate(new Date())}\nScope of the person asking: ${opts.catalog.scope}\nCatalogue: ${JSON.stringify(cat)}\nQuestion: ${q}${feedback}`,
    });
    if (!output.answerable) throw new AiUnavailable(output.reason || "That question is outside what the analytics can answer.");
    const parsed = SpecSchema.safeParse({
      metrics: output.spec.metrics, dims: output.spec.dims,
      filters: output.spec.filters.map((f) => ({ dim: f.dim, op: f.op, value: ["in", "not_in"].includes(f.op) ? f.value : f.value[0] })),
      from: output.spec.from, to: output.spec.to, compare: output.spec.compare === "none" ? null : output.spec.compare,
    });
    if (!parsed.success) { feedback = `\nYour previous spec was invalid: ${parsed.error.issues[0]?.message}. Fix it.`; continue; }
    try {
      const result = await opts.run(parsed.data);
      await attach(logId, parsed.data, result.sql);
      return { title: output.title, viz: output.viz, spec: parsed.data, result, logId };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (/not allowed|not available to your role/i.test(msg)) throw new AiUnavailable("That needs numbers your role cannot see.");
      feedback = `\nThe database refused your previous spec: ${msg}. Fix it using only catalogue keys.`;
    }
  }
  throw new AiUnavailable("Claude could not turn that into a query. Try rephrasing, or build it in the editor.");
}

async function attach(logId: number | null, spec: Spec, sql: unknown) {
  if (logId) await adminClient().rpc("ai_call_attach", { p_id: logId, p_spec: spec, p_sql: sql });
}

// ---------- Explain this chart ----------
const ExplainOut = z.object({ summary: z.string(), points: z.array(z.string()) });

export async function explainChart(opts: { title: string; result: Result; labels: Record<string, string>; userId: string }) {
  const rows = opts.result.rows.slice(0, 200).map((r) => {
    const o: Record<string, unknown> = {};
    opts.result.dims.forEach((d, i) => { o[opts.labels[d] ?? d] = r.k[i]; });
    for (const m of opts.result.metrics) { o[opts.labels[m] ?? m] = r[m]; if (opts.result.compare) o[`${opts.labels[m] ?? m} (previous period)`] = r[`${m}__cmp`]; }
    return o;
  });
  const payload = scrubPii(JSON.stringify({ chart: opts.title, from: opts.result.from, to: opts.result.to, compare: opts.result.compare, scope: opts.result.scope, rows }));
  const { output } = await callClaude({
    purpose: "explain", schema: ExplainOut, userId: opts.userId, question: opts.title, maxTokens: 1500,
    system: "You explain one chart from a sales CRM to the person looking at it. Use only the numbers given. 2-3 plain sentences for the summary, then up to 4 short points: the biggest movement, anything unusual, and what to look at next. No jargon, no hedging, no invented causes.",
    user: payload,
  });
  return output;
}

// ---------- Insights feed ----------
const InsightsOut = z.object({
  items: z.array(z.object({ title: z.string(), body: z.string(), candidate: z.number().int().describe("Index of the candidate this is about") })),
});
type Candidate = { metric: string; dim: string | null; dim_value?: unknown; value: unknown; previous: unknown; spec: Spec };

export async function writeInsights(opts: { roleGroup: string; userId: string }): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("insights_candidates", { p_user: opts.userId });
  if (error) throw new Error(`insights_candidates: ${error.message}`);
  const c = data as { week: { from: string; to: string }; candidates: Candidate[]; labels: Record<string, string> };
  if (!c.candidates.length) return 0;
  const list = c.candidates.map((x, i) => ({ i, metric: c.labels[x.metric] ?? x.metric, by: x.dim, value_of: x.dim_value ?? null, this_week: x.value, last_week: x.previous }));
  const { output, model } = await callClaude({
    purpose: "insights", schema: InsightsOut, userId: opts.userId, maxTokens: 3000,
    system: "You write a short morning feed for a sales CRM team: what changed in the last 7 days against the 7 before, and why it matters. Pick the 3-6 most useful candidates (biggest relative moves with meaningful volume; skip noise). Each item: a title under 70 characters and one or two sentences. Use only the numbers given; never invent causes, say what to check instead.",
    user: scrubPii(JSON.stringify({ week: c.week, candidates: list })),
  });
  const items = output.items.filter((it) => c.candidates[it.candidate]).slice(0, 6).map((it) => {
    const cand = c.candidates[it.candidate]!;
    return { title: it.title.slice(0, 120), body: it.body.slice(0, 400), metric: cand.metric, dim: cand.dim, dim_value: cand.dim_value ?? null, spec: cand.spec };
  });
  const { error: saveError } = await db.rpc("insights_save", { p: { role_group: opts.roleGroup, user_id: opts.roleGroup === "sales" ? opts.userId : null, items, model } });
  if (saveError) throw new Error(`insights_save: ${saveError.message}`);
  return items.length;
}

// ---------- Brief before you call ----------
const BriefOut = z.object({ lines: z.array(z.object({ text: z.string(), source: z.string() })) });
const BRIEF_SYSTEM = `You write "Brief before you call" for an education counsellor about to phone a student about online degrees in India.
Write 3 to 5 short lines (under 200 characters each), most useful first: who the student is, what they want (course, budget, timing), what Witty (the WhatsApp assistant) learned, objections or worries so far, and the partner's history if a partner lost them.
Every line names its source exactly as given in the input: "field:<path>" for a fact from the facts object (for example field:interest.course), "witty:<id>", "activity:<id>", or "partner" for partner history.
Use only what the input says. Never write a phone number or an email address.`;

export async function writeBrief(leadId: number, userId: string | null): Promise<{ lines: { text: string; source: string }[] }> {
  const db = adminClient();
  const { data, error } = await db.rpc("brief_input", { p_lead: leadId });
  if (error) throw new Error(`brief_input: ${error.message}`);
  const input = data as { facts_hash: string; witty: { source: string }[]; activity: { source: string }[] } & Record<string, unknown>;
  const { facts_hash, ...rest } = input;
  const text = JSON.stringify(rest);
  if (containsPii(text)) throw new Error("the brief's input still holds a phone number or email: not sent");
  try {
    const { output, model } = await callClaude({ purpose: "brief", schema: BriefOut, system: BRIEF_SYSTEM, user: text, userId, leadId, maxTokens: 1500 });
    const known = new Set([...input.witty.map((w) => w.source), ...input.activity.map((a) => a.source)]);
    const lines = output.lines
      .map((l) => ({ text: scrubPii(l.text).slice(0, 300), source: l.source.trim() }))
      .filter((l) => l.text.length >= 3 && (l.source === "partner" || /^field:[a-z_.]+$/.test(l.source) || known.has(l.source)))
      .slice(0, 5);
    if (!lines.length) throw new AiUnavailable("Claude's brief had no line tied to the lead's record.");
    const { error: saveError } = await db.rpc("brief_save", { p: { lead_id: leadId, lines, facts_hash, model } });
    if (saveError) throw new Error(`brief_save: ${saveError.message}`);
    return { lines };
  } catch (e) {
    await db.rpc("brief_save", { p: { lead_id: leadId, error: e instanceof Error ? e.message : String(e) } });
    throw e;
  }
}
