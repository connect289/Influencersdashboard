import Link from "next/link";
import { Suspense } from "react";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { SeoNav } from "@/components/admin/SeoNav";
import { COMPANY } from "@/content/site";
import { requireAdmin } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Local SEO" };

interface T { id: number; task: string; done: boolean; done_at: string | null; done_by: string | null }

async function View() {
  const s = await requireAdmin("viewer");
  const { rows } = await rpc<{ rows: T[] }>("web_admin_list", { p_entity: "local_seo", p_search: null, p_limit: 100, p_offset: 0 });
  return (
    <AdminShell session={s} title="Local SEO">
      <SeoNav current="/admin/seo/local" />
      <Card title="On the website">
        <p className="text-muted text-sm">
          The contact page carries <code>EducationalOrganization</code> + <code>LocalBusiness</code> structured data with {COMPANY.address.line1},{" "}
          {COMPANY.address.locality}, {COMPANY.address.city} {COMPANY.address.postalCode} and {COMPANY.phone}. Opening hours are added once set
          (setting <code>business_hours</code>, S-51) — none are shown until then, so nothing is invented.
        </p>
      </Card>
      <Card title="Checklist (manual tasks)">
        <ul className="grid gap-2 text-sm">
          {rows.map((t) => (
            <li key={t.id} className="flex items-start gap-2">
              <span aria-hidden className={t.done ? "text-success" : "text-subtle"}>{t.done ? "✓" : "○"}</span>
              <span>
                {t.task}
                {t.done ? <span className="text-subtle block text-xs">done {t.done_at ? new Date(t.done_at).toLocaleDateString("en-IN") : ""} {t.done_by ? `by ${t.done_by}` : ""}</span> : null}{" "}
                <Link href={`/admin/content/local_seo/edit?key=${encodeURIComponent(JSON.stringify({ id: t.id }))}`} className="text-accent text-xs">update</Link>
              </span>
            </li>
          ))}
        </ul>
      </Card>
    </AdminShell>
  );
}

export default function Page() {
  return <Suspense fallback={<div className="skeleton m-8 h-40" />}><View /></Suspense>;
}
