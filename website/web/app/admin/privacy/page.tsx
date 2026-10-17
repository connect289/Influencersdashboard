import { Suspense } from "react";
import { privacyDoneAction } from "@/app/admin/content-actions";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { requireAdmin, hasRole } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Privacy requests" };

interface Req { id: number; email_norm: string; kind: string; status: string; requested_at: string; processed_at: string | null; processed_by: string | null; note: string | null }

async function View() {
  const s = await requireAdmin("viewer");
  const rows = await rpc<Req[]>("web_admin_privacy_requests");
  return (
    <AdminShell session={s} title="Privacy requests">
      <p className="text-muted max-w-3xl text-sm">
        Deletion, opt-out and data-copy requests from student accounts (DPDP). Complete them within 30 days through the CRM process
        (the website never deletes shared lead data itself), then mark them done here.
      </p>
      <Card>
        <ul className="grid gap-3 text-sm">
          {rows.map((r) => (
            <li key={r.id} className="border-border border-b pb-3 last:border-0">
              <p>
                <strong>{r.kind}</strong> · {r.email_norm} · {new Date(r.requested_at).toLocaleDateString("en-IN")} ·{" "}
                <span className={r.status === "open" ? "text-amber-text font-medium" : "text-muted"}>{r.status}</span>
                {r.processed_by ? <span className="text-muted"> by {r.processed_by}</span> : null}
              </p>
              {r.status === "open" && hasRole(s, "super_admin") ? (
                <form action={privacyDoneAction} className="mt-2 flex flex-wrap items-center gap-2">
                  <input type="hidden" name="id" value={r.id} />
                  <label className="sr-only" htmlFor={`note-${r.id}`}>Note</label>
                  <input id={`note-${r.id}`} name="note" placeholder="Note (what was done)" className="border-border bg-surface h-9 rounded-[var(--radius-md)] border px-2" />
                  <button name="status" value="done" className="bg-primary text-on-primary h-9 rounded-full px-3">Mark done</button>
                  <button name="status" value="rejected" className="border-border h-9 rounded-full border px-3">Reject</button>
                </form>
              ) : null}
            </li>
          ))}
          {rows.length === 0 ? <li className="text-muted">No requests.</li> : null}
        </ul>
      </Card>
    </AdminShell>
  );
}

export default function PrivacyPage() {
  return (
    <Suspense fallback={<div className="skeleton m-8 h-40" />}>
      <View />
    </Suspense>
  );
}
