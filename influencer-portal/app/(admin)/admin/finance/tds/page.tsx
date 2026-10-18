import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { CertificateUpload } from "@/components/finance/certificate-upload";
import { FinanceNav } from "@/components/finance/finance-nav";
import { Badge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { loadTdsSummary } from "@/lib/ledger/data";
import { financialYear, fyQuarter, formatPaise } from "@/lib/format";
import { cn } from "@/lib/utils";

const QUARTERS = ["Q1", "Q2", "Q3", "Q4"] as const;

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("finance.area.tds") };
}

export default async function TdsPage({ searchParams }: { searchParams: Promise<{ fy?: string; q?: string }> }) {
  const { supabase, me } = await requireStaff("tax.manage");
  const t = await getTranslations();
  const sp = await searchParams;
  const now = new Date();
  const currentFy = financialYear(now);
  const fy = /^\d{4}-\d{2}$/.test(sp.fy ?? "") ? (sp.fy as string) : currentFy;
  const quarter = QUARTERS.find((q) => q === sp.q) ?? fyQuarter(now);
  const startYear = Number(currentFy.slice(0, 4));
  const years = [0, 1, 2].map((k) => `${String(startYear - k)}-${String((startYear - k + 1) % 100).padStart(2, "0")}`);
  const summary = await loadTdsSummary(supabase, fy, quarter).catch(() => null);
  return (
    <>
      <PageHeader
        title={t("nav.admin.finance")}
        description={t("finance.tds.subtitle")}
        help="/admin/help/finance#tds"
      />
      <FinanceNav current="tds" permissions={me.permissions} />
      <nav className="mb-3 flex flex-wrap gap-1" aria-label={t("finance.tds.period")}>
        {years.flatMap((y) =>
          QUARTERS.map((q) => (
            <Link
              key={`${y}-${q}`}
              href={`/admin/finance/tds?fy=${y}&q=${q}`}
              aria-current={fy === y && quarter === q ? "page" : undefined}
              className={cn(
                "rounded-lg px-2.5 py-1 text-sm",
                fy === y && quarter === q
                  ? "bg-primary-soft font-medium text-primary"
                  : "text-muted hover:bg-surface-2",
              )}
            >
              {y} {q}
            </Link>
          )),
        )}
      </nav>
      {summary === null ? (
        <ErrorState title={t("errors.loadFailed")} />
      ) : (
        <div className="flex flex-col gap-4">
          <Card>
            <CardHeader
              title={t("finance.tds.bySection", { fy, quarter })}
              description={t("finance.tds.bySectionHint")}
            />
            {summary.sections.length === 0 ? (
              <EmptyState title={t("finance.tds.empty")} description={t("finance.tds.emptyHint")} />
            ) : (
              <Table>
                <thead>
                  <tr>
                    <Th>{t("finance.tds.section")}</Th>
                    <Th className="text-right">{t("finance.tds.base")}</Th>
                    <Th className="text-right">{t("finance.tds.taxable")}</Th>
                    <Th className="text-right">{t("finance.tds.amount")}</Th>
                    <Th>{t("finance.tds.creators")}</Th>
                  </tr>
                </thead>
                <tbody>
                  {summary.sections.map((s) => (
                    <tr key={`${s.section}-${s.borne_by}`}>
                      <Td>
                        {s.section}{" "}
                        {s.borne_by === "eduwit" ? <Badge>{t("finance.payouts.borneByEduwit")}</Badge> : null}
                      </Td>
                      <Td className="text-right tabular-nums">{formatPaise(s.base_paise)}</Td>
                      <Td className="text-right tabular-nums">{formatPaise(s.taxable_paise)}</Td>
                      <Td className="text-right font-medium tabular-nums">{formatPaise(s.amount_paise)}</Td>
                      <Td>{s.creators}</Td>
                    </tr>
                  ))}
                </tbody>
              </Table>
            )}
          </Card>
          <Card>
            <CardHeader title={t("finance.tds.certificates")} description={t("finance.tds.certificatesHint")} />
            {summary.creators.length === 0 ? (
              <EmptyState title={t("finance.tds.noCreators")} />
            ) : (
              <Table>
                <thead>
                  <tr>
                    <Th>{t("finance.ledger.columns.creator")}</Th>
                    <Th>PAN</Th>
                    <Th className="text-right">{t("finance.tds.amount")}</Th>
                    <Th>{t("finance.tds.form16a")}</Th>
                  </tr>
                </thead>
                <tbody>
                  {summary.creators.map((c) => (
                    <tr key={c.creator_id}>
                      <Td>
                        {c.name ?? c.display_name}
                        {c.name && c.name !== c.display_name ? (
                          <span className="block text-xs text-muted">{c.display_name}</span>
                        ) : null}
                      </Td>
                      <Td className="font-mono">{c.pan_last4 ? `•••••${c.pan_last4}` : "—"}</Td>
                      <Td className="text-right tabular-nums">{formatPaise(c.amount_paise)}</Td>
                      <Td>
                        <span className="flex items-center gap-2">
                          {c.certificate ? <Badge family="success">{t("finance.tds.uploaded")}</Badge> : null}
                          <CertificateUpload
                            creatorId={c.creator_id}
                            fy={fy}
                            quarter={quarter}
                            replace={c.certificate === true}
                          />
                        </span>
                      </Td>
                    </tr>
                  ))}
                </tbody>
              </Table>
            )}
          </Card>
        </div>
      )}
    </>
  );
}
