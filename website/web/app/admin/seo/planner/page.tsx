import Link from "next/link";
import { connection } from "next/server";
import { Suspense } from "react";
import { briefAction, draftAction } from "@/app/admin/seo-actions";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { SeoNav } from "@/components/admin/SeoNav";
import { requireAdmin, hasRole } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";
import { refreshReasons, REFRESH_MONTHS, type PageTrend } from "@/lib/seo/refresh";

export const metadata = { title: "Content planner" };

interface R { slug: string; title: string; status: string; author_id: number | null; reviewer_id: number | null; published_at: string | null; refresh_due_at: string | null; updated_at: string; brief: unknown; draft_source: string | null }
const STAGES = ["idea", "brief", "draft", "review", "published", "refresh_due"] as const;

/** The request time (this page renders per request). */
async function requestTime(): Promise<number> {
  await connection();
  return Date.now();
}

async function View({ searchParams }: { searchParams: Promise<{ msg?: string }> }) {
  const [s, sp] = await Promise.all([requireAdmin("viewer"), searchParams]);
  const { rows } = await rpc<{ rows: R[] }>("web_admin_list", { p_entity: "resources", p_search: null, p_limit: 300, p_offset: 0 });
  const edit = hasRole(s, "content_editor");
  const dash = await rpc<{ falling: PageTrend[] }>("web_seo_dashboard", { p_days: 28 });
  const reasons = refreshReasons(rows, dash.falling, await requestTime());
  const due = (r: R) => reasons.has(r.slug);
  return (
    <AdminShell session={s} title="Content planner">
      <SeoNav current="/admin/seo/planner" msg={sp.msg} />
      <p className="text-muted max-w-3xl text-sm">
        Idea → Brief → Draft → Review → Published → Refresh due. Briefs and first drafts can be generated from catalogue facts only
        (Claude-assisted when an API key is set). <strong>Every guide needs a named author and reviewer before it can be published</strong>;
        no mass-generated pages. Published guides past their refresh date, losing Search Console clicks, or older than {REFRESH_MONTHS} months are flagged.
      </p>
      <div className="grid gap-4 xl:grid-cols-3">
        {STAGES.map((st) => {
          const list = rows.filter((r) => (st === "refresh_due" ? r.status === "refresh_due" || due(r) : r.status === st && !(st === "published" && due(r))));
          return (
            <Card key={st} title={`${st.replace("_", " ")} (${list.length})`}>
              <ul className="grid gap-3 text-sm">
                {list.map((r) => (
                  <li key={r.slug} className="border-border border-b pb-2 last:border-0">
                    <Link href={`/admin/content/resources/edit?key=${encodeURIComponent(JSON.stringify({ slug: r.slug }))}`} className="text-accent font-medium">{r.title}</Link>
                    <span className="text-subtle block text-xs">
                      {r.author_id ? "author ✓" : "no author"} · {r.reviewer_id ? "reviewer ✓" : "no reviewer"}{r.draft_source === "claude_assisted" ? " · Claude-assisted draft" : ""}{reasons.has(r.slug) ? ` · refresh: ${reasons.get(r.slug)}` : ""}
                    </span>
                    {edit && (st === "idea" || st === "brief") ? (
                      <span className="mt-1 flex gap-2">
                        <form action={briefAction}><input type="hidden" name="slug" value={r.slug} /><input type="hidden" name="title" value={r.title} /><button className="border-border h-8 rounded-full border px-3 text-xs">{r.brief ? "Regenerate brief" : "Generate brief"}</button></form>
                        {r.brief ? <form action={draftAction}><input type="hidden" name="slug" value={r.slug} /><button className="border-border h-8 rounded-full border px-3 text-xs">First draft</button></form> : null}
                      </span>
                    ) : null}
                  </li>
                ))}
              </ul>
            </Card>
          );
        })}
      </div>
    </AdminShell>
  );
}

export default function Page({ searchParams }: { searchParams: Promise<{ msg?: string }> }) {
  return <Suspense fallback={<div className="skeleton m-8 h-40" />}><View searchParams={searchParams} /></Suspense>;
}
