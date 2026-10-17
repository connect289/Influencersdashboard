import Link from "next/link";
import { Plus } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { ContractsNav } from "@/components/contracts/contracts-nav";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { formatDate } from "@/lib/format";

const row = z.object({
  id: z.uuid(),
  name: z.string(),
  description: z.string().nullable(),
  is_default: z.boolean(),
  archived_at: z.string().nullable(),
  updated_at: z.string(),
  template_clauses: z.array(z.object({ count: z.number() })),
});

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("contracts.area.templates") };
}

export default async function TemplatesPage() {
  const { supabase, me } = await requireStaff("contract.read");
  const t = await getTranslations();
  const { data, error } = await supabase
    .from("contract_templates")
    .select("id, name, description, is_default, archived_at, updated_at, template_clauses(count)")
    .order("archived_at", { nullsFirst: true })
    .order("name");
  const parsed = z.array(row).safeParse(data);
  const canWrite = me.permissions.has("clause.write");
  return (
    <>
      <PageHeader
        title={t("contracts.area.templates")}
        description={t("contracts.templates.subtitle")}
        help="/admin/help/influencer-manager#contracts"
        actions={
          canWrite ? (
            <Button asChild>
              <Link href="/admin/contracts/templates/new">
                <Plus /> {t("contracts.templates.new")}
              </Link>
            </Button>
          ) : null
        }
      />
      <ContractsNav current="templates" />
      <Card>
        {error || !parsed.success ? (
          <ErrorState title={t("errors.loadFailed")} />
        ) : parsed.data.length === 0 ? (
          <EmptyState title={t("contracts.templates.empty")} description={t("contracts.templates.emptyHint")} />
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("contracts.templates.fields.name")}</Th>
                <Th>{t("contracts.templates.clauses")}</Th>
                <Th>{t("contracts.library.updated")}</Th>
              </tr>
            </thead>
            <tbody>
              {parsed.data.map((tp) => (
                <tr key={tp.id} className={tp.archived_at ? "opacity-60" : undefined}>
                  <Td>
                    <Link
                      href={`/admin/contracts/templates/${tp.id}`}
                      className="font-medium text-primary hover:underline"
                    >
                      {tp.name}
                    </Link>
                    {tp.is_default ? (
                      <Badge family="success" className="ml-2">
                        {t("contracts.templates.defaultBadge")}
                      </Badge>
                    ) : null}
                    {tp.archived_at ? <Badge className="ml-2">{t("contracts.library.archivedBadge")}</Badge> : null}
                    {tp.description ? <span className="block text-xs text-muted">{tp.description}</span> : null}
                  </Td>
                  <Td className="tabular">{tp.template_clauses[0]?.count ?? 0}</Td>
                  <Td className="whitespace-nowrap">{formatDate(tp.updated_at)}</Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </>
  );
}
