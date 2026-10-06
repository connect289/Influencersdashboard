import type { Metadata } from "next";
import Link from "next/link";
import { BookOpen, TriangleAlert, Upload } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import { partnerTitle } from "@/lib/partners";
import { programmesOverview } from "@/lib/programmes-data";
import { PartnerLogo } from "../partners/PartnerLogo";

export const metadata: Metadata = { title: "Programme Repository" };

function Bar({ value, total }: { value: number; total: number }) {
  const pct = total ? Math.round((value / total) * 100) : 0;
  return (
    <div className="flex items-center gap-2">
      <div className="h-1.5 w-14 overflow-hidden rounded-full bg-surface-2" aria-hidden><div className="h-full rounded-full bg-success" style={{ width: `${pct}%` }} /></div>
      <span className="tabular text-[12px] text-muted">{pct}%</span>
    </div>
  );
}

export default async function ProgrammesPage() {
  await requireAdmin();
  const o = await programmesOverview();
  const partners = o.partners.filter((p) => p.status !== "closed");
  const totals = o.coverage.reduce((a, c) => ({ programmes: a.programmes + c.programmes, covered: a.covered + c.covered }), { programmes: 0, covered: 0 });

  return (
    <>
      <PageHeader
        title="Programme Repository"
        description="Each partner's own programme file, matched to Eduwit's catalogue. Routing only ever offers a lead to partners whose published file has the programme."
      />

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
        <Card className="min-w-0">
          <CardHeader title="Partners" description="Upload a partner's Excel or CSV file to create a draft; nothing changes until you publish it." />
          {partners.length === 0 ? (
            <EmptyState icon={BookOpen} title="No partners yet" action={<Link href="/partners/new" className={buttonClass("primary", "sm")}>Add a partner</Link>}>
              <p>Add a partner first, then upload its programme file here.</p>
            </EmptyState>
          ) : (
            <ul className="divide-y divide-border">
              {partners.map((p) => (
                <li key={p.id} className="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3.5">
                  <Link href={`/programmes/${p.id}`} className="flex min-w-0 flex-1 items-center gap-3 hover:underline">
                    <PartnerLogo partner={p} />
                    <span className="min-w-0">
                      <span className="block truncate text-[13.5px] font-medium text-fg">{partnerTitle(p)}</span>
                      <span className="block text-[12px] text-subtle">
                        {p.published ? <>v{p.published.version_no} live since <span title={formatDateTime(p.published.published_at)}>{relativeTime(p.published.published_at)}</span></> : "No published file"}
                        {p.source && ` · ${p.source === "gsheet" ? "Google Sheet" : "Excel / CSV"}`}
                      </span>
                    </span>
                  </Link>
                  <div className="flex flex-wrap items-center gap-1.5">
                    <Badge tone={p.live_count ? "success" : "neutral"}><span className="tabular">{p.live_count}</span> live programmes</Badge>
                    {p.draft && (
                      <Link href={`/programmes/${p.id}/versions/${p.draft.id}`}>
                        <Badge tone={p.draft.review ? "warning" : "info"}>Draft v{p.draft.version_no}{p.draft.review ? ` · ${p.draft.review} to review` : " · ready"}</Badge>
                      </Link>
                    )}
                    {p.stale && <Badge tone="warning"><TriangleAlert className="size-3" /> Not updated in {o.stale_days} days</Badge>}
                  </div>
                  <Link href={`/programmes/${p.id}?tab=upload`} className={buttonClass("secondary", "sm")}><Upload className="size-3.5" /> Upload</Link>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card className="min-w-0">
          <CardHeader
            title="Catalogue coverage"
            description={`${totals.covered} of ${totals.programmes} catalogue programmes have at least one partner. Leads for the rest go to B2C.`}
          />
          <div className="overflow-x-auto">
            <table className="w-full text-left text-[13px]">
              <thead className="text-[11px] uppercase tracking-wider text-subtle">
                <tr className="border-b border-border">
                  <th scope="col" className="px-5 py-2.5 font-medium">Course</th>
                  <th scope="col" className="px-3 py-2.5 text-right font-medium">Total</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Covered</th>
                  <th scope="col" className="px-3 py-2.5 text-right font-medium" title="Only one partner offers it">Only 1</th>
                  <th scope="col" className="px-5 py-2.5 text-right font-medium" title="Two or more partners compete">2+</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {o.coverage.map((c) => (
                  <tr key={c.course_key}>
                    <td className="px-5 py-2 font-medium text-fg">{c.course_key.toUpperCase()}</td>
                    <td className="tabular px-3 py-2 text-right text-muted">{c.programmes}</td>
                    <td className="px-3 py-2"><Bar value={c.covered} total={c.programmes} /></td>
                    <td className="tabular px-3 py-2 text-right text-muted">{c.single || "—"}</td>
                    <td className="tabular px-5 py-2 text-right text-muted">{c.competing || "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {o.requests > 0 && (
            <p className="border-t border-border px-5 py-3 text-[12.5px] text-muted">
              <span className="tabular font-medium text-fg">{o.requests}</span> partner {o.requests === 1 ? "programme is" : "programmes are"} waiting to be added to the catalogue.
            </p>
          )}
        </Card>
      </div>
    </>
  );
}
