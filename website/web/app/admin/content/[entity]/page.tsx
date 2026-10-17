import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { AdminShell } from "@/components/admin/AdminShell";
import { entityConfig } from "@/lib/admin/entities";
import { requireAdmin } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Content" };

type Props = { params: Promise<{ entity: string }>; searchParams: Promise<{ q?: string; deleted?: string }> };

const cell = (v: unknown) => (v === null || v === undefined ? "—" : typeof v === "boolean" ? (v ? "Yes" : "No") : typeof v === "object" ? JSON.stringify(v).slice(0, 60) : String(v).slice(0, 90));

async function List({ params, searchParams }: Props) {
  const [{ entity }, sp] = await Promise.all([params, searchParams]);
  const cfg = entityConfig(entity);
  if (!cfg) notFound();
  const s = await requireAdmin("viewer");
  const data = await rpc<{ rows: Record<string, unknown>[] }>("web_admin_list", { p_entity: entity, p_search: sp.q ?? null, p_limit: 200, p_offset: 0 });
  const canEdit = s.role === "super_admin" || (cfg.minRole === "content_editor" && s.role === "content_editor");
  return (
    <AdminShell session={s} title={cfg.label}>
      <p className="text-muted max-w-3xl text-sm">{cfg.description}</p>
      {sp.deleted === "1" ? <p role="status" className="text-success text-sm">Deleted.</p> : null}
      <div className="flex flex-wrap items-center gap-3">
        <form className="flex gap-2" role="search">
          <label htmlFor="q" className="sr-only">Search</label>
          <input id="q" name="q" defaultValue={sp.q ?? ""} placeholder="Search" className="border-border bg-surface h-10 rounded-[var(--radius-md)] border px-3 text-sm" />
          <button className="border-border h-10 rounded-full border px-4 text-sm">Search</button>
        </form>
        {canEdit && cfg.canCreate !== false ? (
          <Link href={`/admin/content/${entity}/edit`} className="bg-primary text-on-primary inline-flex h-10 items-center rounded-full px-4 text-sm font-semibold">
            New {cfg.singular}
          </Link>
        ) : null}
      </div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[40rem] text-left text-sm">
          <thead className="text-muted">
            <tr>
              {cfg.listColumns.map((c) => (
                <th key={c} scope="col" className="border-border border-b px-2 py-2 font-medium">{c.replace(/_/g, " ")}</th>
              ))}
              <th scope="col" className="border-border border-b px-2 py-2"><span className="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody>
            {data.rows.map((r) => {
              const key = Object.fromEntries(cfg.key.map((k) => [k, r[k]]));
              return (
                <tr key={JSON.stringify(key)} className="border-border border-b">
                  {cfg.listColumns.map((c) => (
                    <td key={c} className="px-2 py-2 align-top">{cell(r[c])}</td>
                  ))}
                  <td className="px-2 py-2 text-right">
                    <Link href={`/admin/content/${entity}/edit?key=${encodeURIComponent(JSON.stringify(key))}`} className="text-accent font-medium">
                      {canEdit ? "Edit" : "View"}
                    </Link>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
        {data.rows.length === 0 ? <p className="text-muted py-4 text-sm">Nothing here yet.</p> : null}
      </div>
    </AdminShell>
  );
}

export default function ContentList(props: Props) {
  return (
    <Suspense fallback={<div className="skeleton m-8 h-40" />}>
      <List {...props} />
    </Suspense>
  );
}
