import Link from "next/link";
import { Megaphone } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { relativeTime } from "@/lib/format";
import { formatInr, rate, type CampaignRow, type CapiCampaigns } from "@/lib/capi";

const PLATFORM: Record<CampaignRow["platform"], string> = { meta: "Meta", google: "Google Ads", other: "Other" };

function Pct({ n, of }: { n: number; of: number }) {
  const r = rate(n, of);
  return (
    <td className="tabular px-3 py-2 text-right">
      <span className="text-fg">{n}</span>
      {r !== null && n > 0 && <span className="ml-1 text-[11.5px] text-subtle">{r}%</span>}
    </td>
  );
}

/** Lead quality per paid campaign: how far its leads got, strongest signal first. This is what each platform is told. */
export function Campaigns({ data, days, platform }: { data: CapiCampaigns; days: number; platform: string | null }) {
  const rows = data.campaigns;
  const t = rows.reduce((a, r) => ({ leads: a.leads + r.leads, enrolled: a.enrolled + r.enrolled, applied: a.applied + r.applied, commission: a.commission + Number(r.commission) }),
                        { leads: 0, enrolled: 0, applied: 0, commission: 0 });
  const link = (d: number, p: string | null) => `/capi?tab=campaigns&days=${d}${p ? `&platform=${p}` : ""}`;
  return (
    <Card className="min-w-0">
      <CardHeader title="Lead quality by campaign"
        description="Leads from paid ads in the period, by the campaign that brought them, and how far they got. The ad platforms receive these same signals for their own campaigns, so their bidding learns which campaigns bring students who enrol." />
      <div className="flex flex-wrap items-center gap-1.5 border-b border-border px-5 py-2.5 text-[12.5px]">
        {[30, 90, 180, 365].map((d) => (
          <Link key={d} href={link(d, platform)} className={cn("rounded-md border px-2 py-1", days === d ? "border-amber bg-amber/10 text-fg" : "border-border text-muted hover:text-fg")}>{d} days</Link>
        ))}
        <span className="mx-1 w-px self-stretch bg-border" aria-hidden />
        {([["All", null], ["Meta", "meta"], ["Google", "google"]] as const).map(([l, v]) => (
          <Link key={l} href={link(days, v)} className={cn("rounded-md border px-2 py-1", platform === v ? "border-amber bg-amber/10 text-fg" : "border-border text-muted hover:text-fg")}>{l}</Link>
        ))}
        <span className="ml-auto text-muted">
          {t.leads} paid leads · {t.applied} applicants · {t.enrolled} enrolled · {formatInr(t.commission)} commission
          {data.unpaid > 0 && <> · {data.unpaid} organic or unknown, not reported</>}
        </span>
      </div>
      {rows.length === 0 ? (
        <EmptyState icon={Megaphone} title="No paid leads in this period">
          A lead counts as paid when it came from a Meta lead form that is not organic, or with an ad click (fbclid, gclid, gbraid, wbraid), or with paid UTM tags
          (utm_medium cpc, paid_social…). Leads with UTM tags only are listed but cannot be reported: the platform cannot match them to an ad.
        </EmptyState>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[980px] text-left text-[12.5px]">
            <thead className="text-[11px] uppercase tracking-wider text-subtle">
              <tr className="border-b border-border">
                <th scope="col" className="px-5 py-2 font-medium">Campaign</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">Leads</th>
                <th scope="col" className="px-3 py-2 text-right font-medium" title="Leads the platform can match to its ad (lead form ID or click ID)">Matchable</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">Qualified</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">Interested</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">Applicants</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">Enrolled</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">Junk</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">Commission</th>
                <th scope="col" className="px-5 py-2 text-right font-medium">Events sent</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {rows.map((r) => (
                <tr key={`${r.platform}.${r.campaign_key}`} className="align-top">
                  <td className="max-w-[300px] px-5 py-2">
                    <span className="block truncate font-medium text-fg" title={r.campaign_name ?? r.campaign_key}>{r.campaign_name ?? (r.campaign_id ? `Campaign ${r.campaign_id}` : "(no campaign name)")}</span>
                    <span className="block text-[11.5px] text-subtle">
                      {PLATFORM[r.platform]}{r.campaign_id && <> · <span className="font-mono">{r.campaign_id}</span></>}
                      {r.last_lead_at && <> · last lead {relativeTime(r.last_lead_at)}</>}
                    </span>
                    {r.matchable === 0 && <Badge tone="warning" className="mt-1">UTM only: not reported</Badge>}
                  </td>
                  <td className="tabular px-3 py-2 text-right font-medium text-fg">{r.leads}</td>
                  <Pct n={r.matchable} of={r.leads} />
                  <Pct n={r.qualified} of={r.leads} />
                  <Pct n={r.interested} of={r.leads} />
                  <Pct n={r.applied} of={r.leads} />
                  <td className="tabular px-3 py-2 text-right">
                    <span className={cn(r.enrolled > 0 ? "font-semibold text-success" : "text-fg")}>{r.enrolled}</span>
                    {r.leads > 0 && r.enrolled > 0 && <span className="ml-1 text-[11.5px] text-subtle">{rate(r.enrolled, r.leads)}%</span>}
                    {r.verified > 0 && <span className="block text-[11.5px] text-subtle">{r.verified} verified</span>}
                  </td>
                  <td className={cn("tabular px-3 py-2 text-right", r.junk > 0 ? "text-warning" : "text-subtle")}>{r.junk}</td>
                  <td className="tabular whitespace-nowrap px-3 py-2 text-right">{formatInr(Number(r.commission))}</td>
                  <td className="tabular px-5 py-2 text-right text-muted">{r.events_sent}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <p className="border-t border-border px-5 py-3 text-[12px] text-muted">
        Percentages are of the campaign&apos;s leads. Commission is the expected (or, once verified, realised) net commission of its enrolments.
        A lead belongs to the first paid ad it came from in its current enquiry. Test leads are left out.
      </p>
    </Card>
  );
}
