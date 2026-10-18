import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { FraudActions } from "@/components/leads/fraud-actions";
import { LeadsNav } from "@/components/leads/leads-nav";
import { StatusBadge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { loadFraudQueue } from "@/lib/leads/data";
import { formatDateTime } from "@/lib/format";
import { cn } from "@/lib/utils";

const STATUSES = ["open", "cleared", "confirmed", "all"] as const;

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("leads.area.fraud") };
}

export default async function FraudPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { supabase, me } = await requireStaff("fraud.review");
  const t = await getTranslations();
  const raw = (await searchParams).status;
  const status = STATUSES.find((s) => s === raw) ?? "open";
  const flags = await loadFraudQueue(supabase, status).catch(() => null);
  return (
    <>
      <PageHeader
        title={t("nav.admin.leads")}
        description={t("leads.fraud.subtitle")}
        help="/admin/help/influencer-manager#fraud"
      />
      <LeadsNav current="fraud" permissions={me.permissions} />
      <nav className="-mx-4 mb-3 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0" aria-label={t("leads.fraud.filter")}>
        {STATUSES.map((s) => (
          <Link
            key={s}
            href={`/admin/leads/fraud?status=${s}`}
            aria-current={status === s ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
              status === s ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {t(`leads.fraud.statuses.${s}`)}
          </Link>
        ))}
      </nav>
      <Card>
        {flags === null ? (
          <ErrorState title={t("errors.loadFailed")} />
        ) : flags.length === 0 ? (
          <EmptyState title={t("leads.fraud.empty")} description={t("leads.fraud.emptyHint")} />
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("leads.fraud.columns.signal")}</Th>
                <Th>{t("leads.fraud.columns.creator")}</Th>
                <Th>{t("leads.fraud.columns.lead")}</Th>
                <Th>{t("leads.fraud.columns.status")}</Th>
              </tr>
            </thead>
            <tbody>
              {flags.map((f) => (
                <tr key={f.id}>
                  <Td>
                    <span className="font-medium">{t(`leads.signals.${f.signal}`)}</span>
                    <span className="block text-xs text-muted">
                      {t(
                        `leads.signalDetail.${f.signal}`,
                        Object.fromEntries(Object.entries(f.detail).map(([k, v]) => [k, v])),
                      )}
                    </span>
                    <span className="block text-xs text-muted">{formatDateTime(f.opened_at)}</span>
                  </Td>
                  <Td>
                    <Link href={`/admin/creators/${f.creator_id}`} className="hover:underline">
                      {f.creator_name}
                    </Link>
                  </Td>
                  <Td>
                    {f.attribution_id ? (
                      <Link
                        href={`/admin/leads?lead=${f.attribution_id}`}
                        className="font-mono text-xs text-primary hover:underline"
                      >
                        {f.lead_ref}
                      </Link>
                    ) : (
                      <span className="text-xs text-muted">{t("leads.fraud.creatorLevel")}</span>
                    )}
                  </Td>
                  <Td>
                    {f.status === "open" ? (
                      <FraudActions flagId={f.id} />
                    ) : (
                      <>
                        <StatusBadge
                          status={f.status === "cleared" ? "ok" : "rejected"}
                          label={t(`leads.fraud.statuses.${f.status}`)}
                        />
                        {f.note ? <span className="block text-xs text-muted">{f.note}</span> : null}
                      </>
                    )}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </>
  );
}
