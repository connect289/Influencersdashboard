import Link from "next/link";
import { Suspense } from "react";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { MappingForm } from "@/components/admin/MappingForm";
import { requireAdmin, hasRole } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Taxonomy" };

interface Tax {
  unmapped: { catalog_program_id: number; university: string; course: string; specialization: string; program_name: string; mode: string; reason: string }[];
  programmes: { id: string; label: string }[];
  specialisations: { id: string; label: string }[];
  by_confidence: Record<string, number>;
}

async function View({ searchParams }: { searchParams: Promise<{ id?: string }> }) {
  const [s, sp] = await Promise.all([requireAdmin("viewer"), searchParams]);
  const t = await rpc<Tax>("web_admin_taxonomy");
  return (
    <AdminShell session={s} title="Taxonomy mapping">
      <p className="text-muted max-w-3xl text-sm">
        Every catalogue row maps to one canonical programme and its specialisation(s), so the finder and Witty group it correctly.
        Rows are mapped automatically by rules; anything the rules could not place shows here. Synonyms are edited under{" "}
        <Link href="/admin/content/synonyms" className="text-accent">Search synonyms</Link>.
      </p>
      <Card title="Mapping confidence">
        <ul className="flex flex-wrap gap-4 text-sm">
          {Object.entries(t.by_confidence).map(([k, n]) => (
            <li key={k}>{k}: <span className="tabular font-semibold">{n}</span></li>
          ))}
        </ul>
      </Card>
      <Card title={`Needs a mapping (${t.unmapped.length})`}>
        {t.unmapped.length ? (
          <ul className="grid gap-2 text-sm">
            {t.unmapped.map((u) => (
              <li key={u.catalog_program_id}>
                <Link href={`?id=${u.catalog_program_id}`} className="text-accent">#{u.catalog_program_id}</Link> {u.university} — {u.program_name} ({u.mode}) · <span className="text-muted">{u.reason}</span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-muted text-sm">Every active offering is mapped.</p>
        )}
      </Card>
      {hasRole(s, "content_editor") ? (
        <Card title="Map or re-map an offering">
          <MappingForm programmes={t.programmes} specialisations={t.specialisations} initialId={sp.id ? Number(sp.id) : undefined} />
        </Card>
      ) : null}
    </AdminShell>
  );
}

export default function TaxonomyPage({ searchParams }: { searchParams: Promise<{ id?: string }> }) {
  return (
    <Suspense fallback={<div className="skeleton m-8 h-40" />}>
      <View searchParams={searchParams} />
    </Suspense>
  );
}
