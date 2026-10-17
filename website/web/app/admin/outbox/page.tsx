import { Suspense } from "react";
import { retryOutboxAction } from "@/app/admin/content-actions";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { requireAdmin, hasRole } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Outbox" };

interface Outbox {
  counts: Record<string, number>;
  rows: { id: number; kind: string; status: string; attempts: number; max_attempts: number; last_error: string | null; created_at: string; next_attempt_at: string | null }[];
}

async function View({ searchParams }: { searchParams: Promise<{ status?: string; retried?: string }> }) {
  const [s, sp] = await Promise.all([requireAdmin("viewer"), searchParams]);
  const status = ["pending", "processing", "done", "dead"].includes(sp.status ?? "") ? sp.status! : null;
  const o = await rpc<Outbox>("web_admin_outbox", { p_status: status, p_limit: 200 });
  const fmt = (t: string | null) => (t ? new Date(t).toLocaleString("en-IN", { timeZone: "Asia/Kolkata" }) : "—");
  return (
    <AdminShell session={s} title="Outbox and dead letters">
      <p className="text-muted max-w-3xl text-sm">
        Side effects queued with each lead: confirmation emails, Conversions API events, page revalidation. Failed jobs retry with backoff;
        after the last attempt they become dead letters and wait here. Leads themselves are written directly and never wait on this queue.
      </p>
      {sp.retried ? <p role="status" className="text-success text-sm">Queued for another attempt.</p> : null}
      <nav aria-label="Status" className="flex flex-wrap gap-2 text-sm">
        {[null, "pending", "processing", "done", "dead"].map((st) => (
          <a key={st ?? "all"} href={st ? `?status=${st}` : "?"} aria-current={st === status ? "page" : undefined} className={`border-border rounded-full border px-3 py-1 ${st === status ? "bg-primary text-on-primary" : ""}`}>
            {st ?? "all"} {st ? `(${o.counts[st] ?? 0})` : ""}
          </a>
        ))}
      </nav>
      <Card>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[44rem] text-left text-sm">
            <thead className="text-muted">
              <tr>{["id", "kind", "status", "attempts", "created", "next attempt", "last error", ""].map((h) => <th key={h} scope="col" className="border-border border-b px-2 py-2 font-medium">{h}</th>)}</tr>
            </thead>
            <tbody>
              {o.rows.map((r) => (
                <tr key={r.id} className="border-border border-b align-top">
                  <td className="px-2 py-2">{r.id}</td>
                  <td className="px-2 py-2">{r.kind}</td>
                  <td className={`px-2 py-2 ${r.status === "dead" ? "text-danger font-semibold" : ""}`}>{r.status}</td>
                  <td className="px-2 py-2">{r.attempts}/{r.max_attempts}</td>
                  <td className="px-2 py-2">{fmt(r.created_at)}</td>
                  <td className="px-2 py-2">{r.status === "done" ? "—" : fmt(r.next_attempt_at)}</td>
                  <td className="text-muted max-w-[18rem] px-2 py-2 break-words">{r.last_error ?? ""}</td>
                  <td className="px-2 py-2">
                    {r.status === "dead" && hasRole(s, "super_admin") ? (
                      <form action={retryOutboxAction}>
                        <input type="hidden" name="id" value={r.id} />
                        <button className="text-accent font-medium">Retry</button>
                      </form>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </AdminShell>
  );
}

export default function OutboxPage({ searchParams }: { searchParams: Promise<{ status?: string; retried?: string }> }) {
  return (
    <Suspense fallback={<div className="skeleton m-8 h-40" />}>
      <View searchParams={searchParams} />
    </Suspense>
  );
}
