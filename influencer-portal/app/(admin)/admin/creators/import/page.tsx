import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { ImportWizard } from "@/components/creators/import-wizard";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { formatDateTime } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("creators.import.title") };
}

export default async function ImportPage() {
  const { supabase } = await requireStaff("creator.import");
  const t = await getTranslations();
  const { data: history } = await supabase
    .from("creator_imports")
    .select("id, file_name, total, created, duplicates, errors, created_at")
    .order("created_at", { ascending: false })
    .limit(10);
  return (
    <>
      <Link
        href="/admin/creators"
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.admin.creators")}
      </Link>
      <PageHeader title={t("creators.import.title")} description={t("creators.import.subtitle")} />
      <div className="flex flex-col gap-4">
        <ImportWizard />
        {history?.length ? (
          <Card>
            <CardHeader title={t("creators.import.history")} />
            <Table>
              <thead>
                <tr>
                  <Th>{t("creators.import.file")}</Th>
                  <Th>{t("creators.import.when")}</Th>
                  <Th>{t("creators.import.rows")}</Th>
                  <Th>{t("creators.import.results.created")}</Th>
                  <Th>{t("creators.import.results.duplicate")}</Th>
                  <Th>{t("creators.import.results.error")}</Th>
                </tr>
              </thead>
              <tbody>
                {history.map((h) => (
                  <tr key={h.id}>
                    <Td>{h.file_name}</Td>
                    <Td>{formatDateTime(h.created_at)}</Td>
                    <Td className="tabular-nums">{h.total}</Td>
                    <Td className="tabular-nums">{h.created}</Td>
                    <Td className="tabular-nums">{h.duplicates}</Td>
                    <Td className="tabular-nums">{h.errors}</Td>
                  </tr>
                ))}
              </tbody>
            </Table>
          </Card>
        ) : null}
      </div>
    </>
  );
}
