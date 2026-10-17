import { Suspense } from "react";
import { createGuideIdeaAction, createViewAction } from "@/app/admin/seo-actions";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { SeoNav } from "@/components/admin/SeoNav";
import { requireAdmin, hasRole } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Opportunities" };

interface Opp { query: string; impressions: number; clicks: number; position: number | null; best_page: string | null; question: boolean; filters: Record<string, string[]> }

async function View({ searchParams }: { searchParams: Promise<{ msg?: string }> }) {
  const [s, sp] = await Promise.all([requireAdmin("viewer"), searchParams]);
  const rows = await rpc<Opp[]>("web_seo_opportunities", { p_days: 90 });
  const edit = hasRole(s, "content_editor");
  return (
    <AdminShell session={s} title="Opportunity finder">
      <SeoNav current="/admin/seo/opportunities" msg={sp.msg} />
      <p className="text-muted max-w-3xl text-sm">
        Searches Eduwit already appears for, with no dedicated landing page. One click creates a draft curated finder view (filters
        pre-applied) or, for questions, a guide idea in the planner. Drafts are reviewed before publishing.
      </p>
      <Card>
        <ul className="grid gap-3 text-sm">
          {rows.map((o) => {
            const f = Object.entries(o.filters ?? {}).filter(([k, v]) => ["programme", "spec", "level", "category", "uni", "mode"].includes(k) && v.length);
            return (
              <li key={o.query} className="border-border flex flex-wrap items-center justify-between gap-3 border-b pb-3 last:border-0">
                <span>
                  <strong>{o.query}</strong> <span className="text-muted">· {o.impressions} impressions · {o.clicks} clicks · position {o.position ?? "—"} · now ranking {o.best_page ?? "—"}</span>
                  {f.length ? <span className="text-subtle block text-xs">filters: {f.map(([k, v]) => `${k}=${v.join(",")}`).join(" · ")}</span> : null}
                </span>
                {edit ? (
                  <span className="flex gap-2">
                    {f.length ? (
                      <form action={createViewAction}>
                        <input type="hidden" name="query" value={o.query} />
                        <input type="hidden" name="filters" value={JSON.stringify(o.filters)} />
                        <button className="bg-primary text-on-primary h-9 rounded-full px-3">Create draft view</button>
                      </form>
                    ) : null}
                    {o.question || !f.length ? (
                      <form action={createGuideIdeaAction}>
                        <input type="hidden" name="query" value={o.query} />
                        <button className="border-border h-9 rounded-full border px-3">Add guide idea</button>
                      </form>
                    ) : null}
                  </span>
                ) : null}
              </li>
            );
          })}
          {rows.length === 0 ? <li className="text-muted">No opportunities yet (sync Search Console first).</li> : null}
        </ul>
      </Card>
    </AdminShell>
  );
}

export default function Page({ searchParams }: { searchParams: Promise<{ msg?: string }> }) {
  return <Suspense fallback={<div className="skeleton m-8 h-40" />}><View searchParams={searchParams} /></Suspense>;
}
