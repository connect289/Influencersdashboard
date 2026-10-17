import { Suspense } from "react";
import { decideLinkAction, refreshLinksAction } from "@/app/admin/seo-actions";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { SeoNav } from "@/components/admin/SeoNav";
import { requireAdmin, hasRole } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Internal links" };

interface L { id: number; from_slug: string; to_path: string; anchor: string; reason: string; status: string; decided_by: string | null }

async function View({ searchParams }: { searchParams: Promise<{ msg?: string }> }) {
  const [s, sp] = await Promise.all([requireAdmin("viewer"), searchParams]);
  const rows = await rpc<L[]>("web_link_suggestions_list");
  const edit = hasRole(s, "content_editor");
  return (
    <AdminShell session={s} title="Internal linking engine">
      <SeoNav current="/admin/seo/links" msg={sp.msg} />
      <div className="flex flex-wrap items-center gap-3">
        <p className="text-muted max-w-3xl text-sm">Guides that mention a programme or university get suggested links to the matching curated view or university page. Approved links appear in the guide&apos;s “Related” block.</p>
        {edit ? <form action={refreshLinksAction}><button className="bg-primary text-on-primary h-9 rounded-full px-4 text-sm">Find new suggestions</button></form> : null}
      </div>
      <Card>
        <ul className="grid gap-2 text-sm">
          {rows.map((l) => (
            <li key={l.id} className="border-border flex flex-wrap items-center justify-between gap-2 border-b pb-2 last:border-0">
              <span>/resources/{l.from_slug} → <strong>{l.to_path}</strong> as “{l.anchor}” <span className="text-subtle">({l.reason}) · {l.status}{l.decided_by ? ` by ${l.decided_by}` : ""}</span></span>
              {edit && l.status === "suggested" ? (
                <form action={decideLinkAction} className="flex gap-2">
                  <input type="hidden" name="id" value={l.id} />
                  <button name="status" value="approved" className="bg-primary text-on-primary h-8 rounded-full px-3 text-xs">Approve</button>
                  <button name="status" value="rejected" className="border-border h-8 rounded-full border px-3 text-xs">Reject</button>
                </form>
              ) : null}
            </li>
          ))}
          {rows.length === 0 ? <li className="text-muted">No suggestions yet (they need published guides).</li> : null}
        </ul>
      </Card>
    </AdminShell>
  );
}

export default function Page({ searchParams }: { searchParams: Promise<{ msg?: string }> }) {
  return <Suspense fallback={<div className="skeleton m-8 h-40" />}><View searchParams={searchParams} /></Suspense>;
}
