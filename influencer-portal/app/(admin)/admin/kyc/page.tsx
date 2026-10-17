import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { StatusBadge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { formatDateTime, formatRelative } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.kyc") };
}

/** KYC waiting for verification, oldest first. */
export default async function KycQueuePage() {
  const { supabase } = await requireStaff("kyc.read_masked");
  const t = await getTranslations();
  const { data, error } = await supabase.rpc("kyc_queue");
  const rows = data ?? [];
  return (
    <>
      <PageHeader
        title={t("kyc.queue.title")}
        description={t("kyc.queue.subtitle")}
        help="/admin/help/finance#kyc"
      />
      <Card>
        {error ? (
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        ) : null}
        {!error && rows.length === 0 ? (
          <EmptyState title={t("kyc.queue.empty")} description={t("kyc.queue.emptyHint")} />
        ) : null}
        {rows.length > 0 ? (
          <Table>
            <thead>
              <tr>
                <Th>{t("kyc.queue.creator")}</Th>
                <Th>{t("kyc.fields.gstStatus")}</Th>
                <Th>{t("kyc.queue.submitted")}</Th>
                <Th>{t("kyc.queue.status")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.creator_id}>
                  <Td>
                    <Link
                      href={`/admin/kyc/${r.creator_id}`}
                      className="font-medium text-primary hover:underline"
                    >
                      {r.display_name}
                    </Link>
                    <span className="block text-xs text-muted">@{r.handle}</span>
                  </Td>
                  <Td>
                    {t(`kyc.gst.${r.gst_status as "unregistered" | "registered" | "composition"}`)}
                  </Td>
                  <Td>
                    <span title={formatDateTime(r.submitted_at)}>
                      {formatRelative(r.submitted_at)}
                    </span>
                  </Td>
                  <Td>
                    <StatusBadge
                      status={r.status}
                      label={t(`kyc.status.${r.status as "submitted"}`)}
                    />
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        ) : null}
      </Card>
    </>
  );
}
