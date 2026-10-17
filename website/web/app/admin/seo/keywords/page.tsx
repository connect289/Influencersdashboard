import Link from "next/link";
import { Suspense } from "react";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { SeoNav } from "@/components/admin/SeoNav";
import { requireAdmin } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Keywords" };

interface K { id: number; keyword: string; priority: number; target_path: string | null; position: number | null; target_position: number | null; ranking_pages: string[]; cannibalised: boolean }

async function View() {
  const s = await requireAdmin("viewer");
  const rows = await rpc<K[]>("web_seo_keywords_report", { p_days: 28 });
  return (
    <AdminShell session={s} title="Keyword list">
      <SeoNav current="/admin/seo/keywords" />
      <p className="text-muted max-w-3xl text-sm">
        Target keywords with priority and landing page; positions come from Search Console (28 days). “Cannibalised” means two or more
        pages compete for the same keyword. <Link href="/admin/content/keywords/edit" className="text-accent">Add a keyword</Link>.
      </p>
      <Card>
        <table className="w-full text-left text-sm">
          <thead className="text-muted"><tr>{["keyword", "priority", "target page", "position", "target position", "ranking pages", ""].map((h) => <th key={h} scope="col" className="border-border border-b py-1 pr-2 font-medium">{h}</th>)}</tr></thead>
          <tbody>
            {rows.map((k) => (
              <tr key={k.id} className="border-border border-b align-top">
                <td className="py-1 pr-2">{k.keyword}</td>
                <td className="py-1 pr-2">P{k.priority}</td>
                <td className="py-1 pr-2">{k.target_path ?? "—"}</td>
                <td className="py-1 pr-2">{k.position ?? "—"}</td>
                <td className="py-1 pr-2">{k.target_position ?? "—"}</td>
                <td className="py-1 pr-2">{k.ranking_pages.join(", ") || "—"}{k.cannibalised ? <span className="text-danger block text-xs font-medium">cannibalised</span> : null}</td>
                <td className="py-1 pr-2"><Link href={`/admin/content/keywords/edit?key=${encodeURIComponent(JSON.stringify({ id: k.id }))}`} className="text-accent">Edit</Link></td>
              </tr>
            ))}
          </tbody>
        </table>
        {rows.length === 0 ? <p className="text-muted py-3 text-sm">No keywords yet.</p> : null}
      </Card>
    </AdminShell>
  );
}

export default function Page() {
  return <Suspense fallback={<div className="skeleton m-8 h-40" />}><View /></Suspense>;
}
