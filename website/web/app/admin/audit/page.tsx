import { Suspense } from "react";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { requireAdmin } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Audit log" };

interface Row { id: number; actor_email: string | null; action: string; entity: string; entity_id: string | null; before: unknown; after: unknown; at: string }

async function View({ searchParams }: { searchParams: Promise<{ entity?: string }> }) {
  const [s, sp] = await Promise.all([requireAdmin("viewer"), searchParams]);
  const rows = await rpc<Row[]>("web_admin_audit", { p_entity: sp.entity && /^[a-z_.]{1,60}$/.test(sp.entity) ? sp.entity : null, p_limit: 300 });
  return (
    <AdminShell session={s} title="Audit log">
      <p className="text-muted text-sm">Every admin change, settings change, mapping and privacy action, newest first.</p>
      <Card>
        <ul className="grid gap-2 text-sm">
          {rows.map((r) => (
            <li key={r.id} className="border-border border-b pb-2 last:border-0">
              <span className="text-muted">{new Date(r.at).toLocaleString("en-IN", { timeZone: "Asia/Kolkata" })}</span> · <strong>{r.action}</strong>{" "}
              <a href={`?entity=${r.entity}`} className="text-accent">{r.entity}</a> {r.entity_id ?? ""} · {r.actor_email ?? "system"}
              {r.after || r.before ? (
                <details className="mt-1">
                  <summary className="text-subtle cursor-pointer text-xs">Changes</summary>
                  <pre className="bg-surface-hover mt-1 overflow-x-auto rounded p-2 text-xs">{JSON.stringify({ before: r.before, after: r.after }, null, 2)}</pre>
                </details>
              ) : null}
            </li>
          ))}
        </ul>
      </Card>
    </AdminShell>
  );
}

export default function AuditPage({ searchParams }: { searchParams: Promise<{ entity?: string }> }) {
  return (
    <Suspense fallback={<div className="skeleton m-8 h-40" />}>
      <View searchParams={searchParams} />
    </Suspense>
  );
}
