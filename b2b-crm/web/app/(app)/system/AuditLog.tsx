import Link from "next/link";
import { ScrollText } from "lucide-react";
import { Badge, EmptyState } from "@/components/ui/Card";
import { buttonClass } from "@/components/ui/Button";
import { formatDateTime, relativeTime } from "@/lib/format";
import type { AuditPage } from "@/lib/integrations";

const ACTOR_TONE: Record<string, "brand" | "neutral" | "info" | "warning"> = { admin: "brand", engine: "neutral", system: "neutral", b2c_crm: "info", api: "info", partner: "warning" };

function summary(p: Record<string, unknown>): string {
  const skip = new Set(["record", "candidates", "truncated", "keys"]);
  const parts: string[] = [];
  for (const [k, v] of Object.entries(p)) {
    if (skip.has(k) || v === null || v === undefined || v === "") continue;
    const s = typeof v === "object" ? JSON.stringify(v) : String(v);
    parts.push(`${k}: ${s.length > 60 ? `${s.slice(0, 57)}…` : s}`);
    if (parts.length >= 5) break;
  }
  return parts.join(" · ");
}

/** M33c: the append-only event log, filtered. Links go to the lead or the partner. */
export function AuditLog({ page, filters }: { page: AuditPage; filters: { actor_type: string; q: string } }) {
  const next = page.next_after ? `/system?tab=audit&actor=${filters.actor_type}&q=${encodeURIComponent(filters.q)}&after=${page.next_after}` : null;
  return (
    <>
      <form className="flex flex-wrap items-center gap-2 border-b border-border px-5 py-3 text-[13px]" method="get" action="/system">
        <input type="hidden" name="tab" value="audit" />
        <label className="flex items-center gap-1.5 text-muted">Who
          <select name="actor" defaultValue={filters.actor_type} className="h-8 rounded-lg border border-border bg-surface px-2 text-fg">
            <option value="admin">Admins</option><option value="b2c_crm">B2C CRM</option><option value="api">API keys</option><option value="engine">The engine</option><option value="system">System</option><option value="all">Everyone</option>
          </select></label>
        <input name="q" defaultValue={filters.q} placeholder="Event contains… e.g. settings, live_switch, merged" className="h-8 min-w-[240px] flex-1 rounded-lg border border-border bg-surface px-2.5 text-fg placeholder:text-subtle" />
        <button type="submit" className={buttonClass("secondary", "sm")}>Filter</button>
      </form>
      {page.rows.length === 0 ? <EmptyState icon={ScrollText} title="Nothing logged for these filters" /> : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[760px] text-left text-[12.5px]">
            <thead className="text-[11px] uppercase tracking-wider text-subtle">
              <tr className="border-b border-border">
                <th scope="col" className="px-5 py-2 font-medium">When</th>
                <th scope="col" className="px-3 py-2 font-medium">Who</th>
                <th scope="col" className="px-3 py-2 font-medium">What</th>
                <th scope="col" className="px-3 py-2 font-medium">On</th>
                <th scope="col" className="px-5 py-2 font-medium">Details</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {page.rows.map((r) => (
                <tr key={r.id}>
                  <td className="whitespace-nowrap px-5 py-2 text-muted" title={formatDateTime(r.at)}>{relativeTime(r.at)}</td>
                  <td className="px-3 py-2"><Badge tone={ACTOR_TONE[r.actor_type] ?? "neutral"}>{r.actor_email ?? r.actor_type}</Badge></td>
                  <td className="px-3 py-2 font-mono text-[12px] text-fg">{r.type}</td>
                  <td className="whitespace-nowrap px-3 py-2">
                    {r.lead_id && <Link href={`/leads?lead=${r.lead_id}`} className="text-fg hover:underline">lead #{r.lead_id}</Link>}
                    {r.partner_id && <> {r.lead_id ? "· " : ""}<Link href={`/partners/${r.partner_id}`} className="text-fg hover:underline">{r.partner_name ?? `partner #${r.partner_id}`}</Link></>}
                  </td>
                  <td className="max-w-[480px] truncate px-5 py-2 text-muted" title={JSON.stringify(r.payload)}>{summary(r.payload)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {next && <div className="border-t border-border px-5 py-3"><Link href={next} className={buttonClass("secondary", "sm")}>Older</Link></div>}
        </div>
      )}
    </>
  );
}
