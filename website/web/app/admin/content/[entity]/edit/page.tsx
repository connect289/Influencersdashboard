import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { deleteEntityAction } from "@/app/admin/content-actions";
import { AdminShell } from "@/components/admin/AdminShell";
import { EntityForm } from "@/components/admin/EntityForm";
import { entityConfig } from "@/lib/admin/entities";
import { requireAdmin } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Edit" };

type Props = { params: Promise<{ entity: string }>; searchParams: Promise<{ key?: string; saved?: string }> };

async function Edit({ params, searchParams }: Props) {
  const [{ entity }, sp] = await Promise.all([params, searchParams]);
  const cfg = entityConfig(entity);
  if (!cfg) notFound();
  const s = await requireAdmin("viewer");
  let key: Record<string, unknown> | null = null;
  try {
    key = sp.key ? (JSON.parse(sp.key) as Record<string, unknown>) : null;
  } catch {
    notFound();
  }
  const row = key ? await rpc<Record<string, unknown> | null>("web_admin_get", { p_entity: entity, p_key: key }) : null;
  if (key && !row) notFound();
  const canEdit = s.role === "super_admin" || (cfg.minRole === "content_editor" && s.role === "content_editor");
  if (!key && (!canEdit || cfg.canCreate === false)) notFound();
  const keyJson = key ? JSON.stringify(key) : null;
  return (
    <AdminShell session={s} title={key ? `Edit ${cfg.singular}` : `New ${cfg.singular}`}>
      <Link href={`/admin/content/${entity}`} className="text-accent text-sm">← {cfg.label}</Link>
      <EntityForm cfg={cfg} row={row} keyJson={keyJson} canEdit={canEdit} saved={sp.saved === "1"} />
      {key && canEdit && cfg.canDelete ? (
        <form action={deleteEntityAction} className="border-border mt-4 max-w-3xl border-t pt-4">
          <input type="hidden" name="__entity" value={entity} />
          <input type="hidden" name="__key" value={keyJson!} />
          <button type="submit" className="border-danger text-danger h-10 rounded-full border px-4 text-sm">
            Delete this {cfg.singular}
          </button>
        </form>
      ) : null}
    </AdminShell>
  );
}

export default function EditPage(props: Props) {
  return (
    <Suspense fallback={<div className="skeleton m-8 h-40" />}>
      <Edit {...props} />
    </Suspense>
  );
}
