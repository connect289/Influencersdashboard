import { Suspense } from "react";
import { redirect404Action } from "@/app/admin/seo-actions";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { SeoNav } from "@/components/admin/SeoNav";
import { requireAdmin, hasRole } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "404s and redirects" };

interface R { misses: { path: string; hits: number; last_seen: string; last_referrer: string | null }[]; chains: { from: string; via: string; to: string }[] }

async function View({ searchParams }: { searchParams: Promise<{ msg?: string }> }) {
  const [s, sp] = await Promise.all([requireAdmin("viewer"), searchParams]);
  const r = await rpc<R>("web_404_report");
  const edit = hasRole(s, "content_editor");
  return (
    <AdminShell session={s} title="404 monitor and redirects">
      <SeoNav current="/admin/seo/404" msg={sp.msg} />
      <Card title="Pages not found">
        <ul className="grid gap-2 text-sm">
          {r.misses.map((m) => (
            <li key={m.path} className="border-border flex flex-wrap items-center justify-between gap-2 border-b pb-2 last:border-0">
              <span><strong>{m.path}</strong> <span className="text-muted">· {m.hits} hit(s) · last {new Date(m.last_seen).toLocaleDateString("en-IN")}{m.last_referrer ? ` · from ${m.last_referrer}` : ""}</span></span>
              {edit ? (
                <form action={redirect404Action} className="flex gap-2">
                  <input type="hidden" name="path" value={m.path} />
                  <label className="sr-only" htmlFor={`to-${m.path}`}>Redirect {m.path} to</label>
                  <input id={`to-${m.path}`} name="to" placeholder="/programmes" required className="border-border bg-surface h-8 w-48 rounded-[var(--radius-md)] border px-2" />
                  <button className="bg-primary text-on-primary h-8 rounded-full px-3 text-xs">Redirect (301)</button>
                </form>
              ) : null}
            </li>
          ))}
          {r.misses.length === 0 ? <li className="text-muted">No unresolved 404s.</li> : null}
        </ul>
      </Card>
      <Card title="Redirect chains">
        {r.chains.length ? (
          <ul className="grid gap-1 text-sm">{r.chains.map((c) => <li key={c.from}>{c.from} → {c.via} → {c.to} <span className="text-amber-text">(point {c.from} straight at {c.to})</span></li>)}</ul>
        ) : (
          <p className="text-muted text-sm">None.</p>
        )}
      </Card>
    </AdminShell>
  );
}

export default function Page({ searchParams }: { searchParams: Promise<{ msg?: string }> }) {
  return <Suspense fallback={<div className="skeleton m-8 h-40" />}><View searchParams={searchParams} /></Suspense>;
}
