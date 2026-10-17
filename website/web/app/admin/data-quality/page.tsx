import { Suspense } from "react";
import { AdminShell, Card, Stat } from "@/components/admin/AdminShell";
import { requireAdmin } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Data quality" };

type DQ = Record<string, unknown> & {
  offerings_total: number;
  visible: number;
  no_fee: number;
  no_min_pct: number;
  no_duration: number;
  ug_requires_bachelor: number;
  needs_review: number;
  zero_result_searches_7d: number;
  refreshed_at: string;
  universities_without_ugc_deb: string[];
  universities_without_naac_grade: string[];
  hidden_by_reason: Record<string, number>;
  stale_last_verified?: number;
};

async function View() {
  const s = await requireAdmin("viewer");
  const d = await rpc<DQ>("web_data_quality");
  return (
    <AdminShell session={s} title="Data quality">
      <p className="text-muted max-w-3xl text-sm">
        Problems in the shared catalogue that affect what students see. Fix them in the catalogue (CRM), not here; the site refreshes
        within minutes. Read model refreshed {new Date(d.refreshed_at).toLocaleString("en-IN", { timeZone: "Asia/Kolkata" })}.
      </p>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Stat label="Offerings (visible / total)" value={`${d.visible} / ${d.offerings_total}`} />
        <Stat label="Missing fees" value={d.no_fee} />
        <Stat label="Missing minimum %" value={d.no_min_pct} />
        <Stat label="Duration unknown" value={d.no_duration} />
        <Stat label="UG rows asking for a bachelor's" value={d.ug_requires_bachelor} />
        <Stat label="Mappings to review" value={d.needs_review} href="/admin/taxonomy" />
        <Stat label="Zero-result searches (7 days)" value={d.zero_result_searches_7d} />
        {typeof d.stale_last_verified === "number" ? <Stat label="Stale “last verified”" value={d.stale_last_verified} /> : null}
      </div>
      <div className="grid gap-4 xl:grid-cols-2">
        <Card title="Universities without a UGC-DEB status">
          <ul className="list-disc pl-5 text-sm">{d.universities_without_ugc_deb.map((u) => <li key={u}>{u}</li>)}</ul>
        </Card>
        <Card title="Universities without a NAAC grade">
          <ul className="list-disc pl-5 text-sm">{d.universities_without_naac_grade.map((u) => <li key={u}>{u}</li>)}</ul>
        </Card>
        <Card title="Hidden offerings">
          <ul className="text-sm">{Object.entries(d.hidden_by_reason).map(([k, n]) => <li key={k}>{k}: {n}</li>)}</ul>
        </Card>
      </div>
    </AdminShell>
  );
}

export default function DataQualityPage() {
  return (
    <Suspense fallback={<div className="skeleton m-8 h-40" />}>
      <View />
    </Suspense>
  );
}
