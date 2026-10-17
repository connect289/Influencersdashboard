import { Suspense } from "react";
import { runChecksAction } from "@/app/admin/seo-actions";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { SeoNav } from "@/components/admin/SeoNav";
import { requireAdmin, hasRole } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "On-page checks" };

interface C { path: string; score: number; issues: { rule: string; severity: string; message: string }[]; checked_at: string }

async function View({ searchParams }: { searchParams: Promise<{ msg?: string }> }) {
  const [s, sp] = await Promise.all([requireAdmin("viewer"), searchParams]);
  const rows = await rpc<C[]>("web_seo_checks_list");
  return (
    <AdminShell session={s} title="On-page checker">
      <SeoNav current="/admin/seo/checks" msg={sp.msg} />
      <div className="flex flex-wrap items-center gap-3">
        <p className="text-muted max-w-3xl text-sm">
          Every curated view, university page and guide: title and description length and uniqueness, H1, heading order, intro, FAQs,
          structured data, image alt text, internal links in and out, broken links and banned claims. Runs daily and on demand.
        </p>
        {hasRole(s, "content_editor") ? <form action={runChecksAction}><button className="bg-primary text-on-primary h-9 rounded-full px-4 text-sm">Run checks now</button></form> : null}
      </div>
      <Card>
        <ul className="grid gap-2 text-sm">
          {rows.map((c) => (
            <li key={c.path} className="border-border border-b pb-2 last:border-0">
              <details>
                <summary className="cursor-pointer">
                  <span className={`tabular mr-2 inline-block w-10 font-semibold ${c.score >= 90 ? "text-success" : c.score >= 70 ? "text-amber-text" : "text-danger"}`}>{c.score}</span>
                  {c.path} <span className="text-subtle text-xs">· {c.issues.length} issue(s)</span>
                </summary>
                <ul className="mt-2 grid gap-1 pl-12">
                  {c.issues.map((i) => <li key={i.rule}><span className={i.severity === "error" ? "text-danger" : "text-amber-text"}>{i.severity}</span> · {i.message}</li>)}
                  {c.issues.length === 0 ? <li className="text-success">No issues.</li> : null}
                </ul>
              </details>
            </li>
          ))}
          {rows.length === 0 ? <li className="text-muted">Not run yet.</li> : null}
        </ul>
      </Card>
    </AdminShell>
  );
}

export default function Page({ searchParams }: { searchParams: Promise<{ msg?: string }> }) {
  return <Suspense fallback={<div className="skeleton m-8 h-40" />}><View searchParams={searchParams} /></Suspense>;
}
