import Link from "next/link";
import { Plus } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { AgencyDialog } from "@/components/agency/agency-dialog";
import { StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { formatDate } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.agencies") };
}

export default async function AgenciesPage() {
  const { supabase } = await requireStaff("agency.manage");
  const t = await getTranslations();
  const [agencies, members, links] = await Promise.all([
    supabase.from("agencies").select("id, name, status, created_at").order("name"),
    supabase.from("agency_members").select("agency_id").eq("status", "active"),
    supabase.from("agency_creator_links").select("agency_id").eq("status", "active"),
  ]);
  const count = (rows: { agency_id: string }[] | null, id: string) =>
    (rows ?? []).filter((r) => r.agency_id === id).length;
  const rows = agencies.data ?? [];
  const add = (
    <AgencyDialog
      trigger={
        <Button>
          <Plus /> {t("agencies.add")}
        </Button>
      }
    />
  );
  return (
    <>
      <PageHeader title={t("nav.admin.agencies")} description={t("agencies.subtitle")} actions={add} />
      <Card>
        {agencies.error ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
        {!agencies.error && rows.length === 0 ? (
          <EmptyState title={t("agencies.empty")} description={t("agencies.emptyHint")} />
        ) : null}
        {rows.length > 0 ? (
          <Table>
            <thead>
              <tr>
                <Th>{t("agencies.fields.name")}</Th>
                <Th>{t("agencies.members.title")}</Th>
                <Th>{t("agencies.linkedCreators")}</Th>
                <Th>{t("agencies.added")}</Th>
                <Th>{t("agencies.status")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((a) => (
                <tr key={a.id}>
                  <Td>
                    <Link href={`/admin/agencies/${a.id}`} className="font-medium text-primary hover:underline">
                      {a.name}
                    </Link>
                  </Td>
                  <Td className="tabular-nums">{count(members.data, a.id)}</Td>
                  <Td className="tabular-nums">{count(links.data, a.id)}</Td>
                  <Td>{formatDate(a.created_at)}</Td>
                  <Td>
                    <StatusBadge
                      status={a.status}
                      label={t(`agencies.statuses.${a.status as "active" | "suspended"}`)}
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
