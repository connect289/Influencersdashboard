import { Suspense } from "react";
import { AdminShell, Card, Stat } from "@/components/admin/AdminShell";
import { scrubString } from "@/lib/security/scrub";
import { requireAdmin } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Insights" };

type Step = { step: string; n: number };
interface Insights {
  conversations: number;
  turns: number;
  handoffs: number;
  by_classification: Record<string, number>;
  tokens: number;
  cached_tokens: number;
  cost_usd: number;
  avg_latency_ms: number | null;
  avg_ttft_ms: number | null;
  fallback_replies: number;
  top_questions: { text: string; n: number }[];
  thumbs_down: { at: string; reply: string; mode: string; question: string | null }[];
  thumbs_up: number;
}

function Funnel({ steps }: { steps: Step[] }) {
  const max = Math.max(1, ...steps.map((s) => s.n));
  return (
    <ol className="grid gap-2">
      {steps.map((s, i) => (
        <li key={s.step} className="grid grid-cols-[12rem_1fr_4rem] items-center gap-3 text-sm">
          <span>{s.step}</span>
          <span className="bg-surface-hover h-3 overflow-hidden rounded-full" aria-hidden>
            <span className="bg-primary block h-full rounded-full" style={{ width: `${(s.n / max) * 100}%` }} />
          </span>
          <span className="tabular text-right">
            {s.n}
            {i > 0 && steps[i - 1]!.n > 0 ? <span className="text-subtle block text-xs">{Math.round((s.n / steps[i - 1]!.n) * 100)}%</span> : null}
          </span>
        </li>
      ))}
    </ol>
  );
}

async function View({ searchParams }: { searchParams: Promise<{ days?: string }> }) {
  const [s, sp] = await Promise.all([requireAdmin("viewer"), searchParams]);
  const days = [7, 30, 90].includes(Number(sp.days)) ? Number(sp.days) : 30;
  const [f, a] = await Promise.all([
    rpc<{ gate: Step[]; form: Step[]; enquiry: Step[] }>("web_admin_funnels", { p_days: days }),
    rpc<Insights>("web_admin_advisor_insights", { p_days: days }),
  ]);
  return (
    <AdminShell session={s} title="Funnels and Witty insights">
      <nav aria-label="Period" className="flex gap-2 text-sm">
        {[7, 30, 90].map((d) => (
          <a key={d} href={`?days=${d}`} aria-current={d === days ? "page" : undefined} className={`border-border rounded-full border px-3 py-1 ${d === days ? "bg-primary text-on-primary" : ""}`}>
            {d} days
          </a>
        ))}
      </nav>
      <div className="grid gap-4 xl:grid-cols-2">
        <Card title="Witty gate funnel">
          <Funnel steps={f.gate} />
        </Card>
        <Card title="Application form funnel">
          <Funnel steps={f.form} />
        </Card>
        <Card title="Enquiry form">
          <Funnel steps={f.enquiry} />
        </Card>
      </div>
      <h2 className="text-lg font-semibold">Witty</h2>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Stat label="Conversations" value={a.conversations} />
        <Stat label="Hand-offs to a counsellor" value={a.handoffs} />
        <Stat label="Average reply time" value={a.avg_latency_ms ? `${(a.avg_latency_ms / 1000).toFixed(1)} s` : "—"} />
        <Stat label="Time to first token" value={a.avg_ttft_ms ? `${(a.avg_ttft_ms / 1000).toFixed(1)} s` : "—"} />
        <Stat label="Tokens (cached)" value={`${a.tokens} (${a.cached_tokens})`} />
        <Stat label="Model cost (USD)" value={a.cost_usd} />
        <Stat label="Safe fallback replies" value={a.fallback_replies} />
        <Stat label="Thumbs up / down" value={`${a.thumbs_up} / ${a.thumbs_down.length}`} />
      </div>
      <div className="grid gap-4 xl:grid-cols-2">
        <Card title="Classification">
          <ul className="grid gap-1 text-sm">
            {Object.entries(a.by_classification).map(([k, n]) => (
              <li key={k} className="flex justify-between"><span>{k}</span><span className="tabular">{n}</span></li>
            ))}
          </ul>
        </Card>
        <Card title="Top first questions">
          <ol className="grid list-decimal gap-1 pl-5 text-sm">
            {a.top_questions.map((q) => (
              <li key={q.text}>{scrubString(q.text)} <span className="text-subtle">({q.n})</span></li>
            ))}
          </ol>
        </Card>
      </div>
      <Card title="Thumbs-down answers">
        {a.thumbs_down.length ? (
          <ul className="grid gap-3 text-sm">
            {a.thumbs_down.map((t) => (
              <li key={t.at} className="border-border border-b pb-3 last:border-0">
                <p className="text-muted">Q: {t.question ? scrubString(t.question) : "—"}</p>
                <p>A ({t.mode}): {scrubString(t.reply)}</p>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-muted text-sm">None in this period.</p>
        )}
        <p className="text-subtle mt-3 text-xs">Prompts are not edited here: they belong to the shared agent core (Witty).</p>
      </Card>
    </AdminShell>
  );
}

export default function InsightsPage({ searchParams }: { searchParams: Promise<{ days?: string }> }) {
  return (
    <Suspense fallback={<div className="skeleton m-8 h-40" />}>
      <View searchParams={searchParams} />
    </Suspense>
  );
}
