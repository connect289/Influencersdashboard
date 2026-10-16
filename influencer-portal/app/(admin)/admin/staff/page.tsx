import { UserPlus } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { StaffDialog } from "@/components/staff/staff-dialog";
import { StaffRowActions } from "@/components/staff/staff-row-actions";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { isStaffRole, ROLE_LABELS } from "@/lib/auth/permissions";
import { formatRelative } from "@/lib/format";

interface StaffRow {
  user_id: string;
  full_name: string;
  email: string;
  status: string;
  is_signatory: boolean;
  signatory_designation: string | null;
  roles: string[];
  last_seen_at: string | null;
}

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.staff") };
}

export default async function StaffPage() {
  const { supabase, me } = await requireStaff("staff.manage");
  const t = await getTranslations();
  const { data, error } = await supabase.rpc("staff_list");
  const rows = (data ?? []) as StaffRow[];
  return (
    <>
      <PageHeader
        title={t("nav.admin.staff")}
        description={t("staff.subtitle")}
        actions={
          <StaffDialog
            invite
            trigger={
              <Button>
                <UserPlus /> {t("staff.invite")}
              </Button>
            }
          />
        }
      />
      {error ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
      {!error && rows.length === 0 ? <EmptyState title={t("staff.empty")} /> : null}
      {rows.length > 0 ? (
        <Card className="p-0 md:p-0">
          <Table>
            <thead>
              <tr>
                <Th>{t("staff.fields.name")}</Th>
                <Th>{t("staff.fields.roles")}</Th>
                <Th>{t("staff.fields.status")}</Th>
                <Th>{t("staff.fields.lastSeen")}</Th>
                <Th className="text-right">
                  <span className="sr-only">{t("common.actions")}</span>
                </Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.user_id}>
                  <Td>
                    <span className="block font-medium">{r.full_name}</span>
                    <span className="block text-xs text-muted">{r.email}</span>
                  </Td>
                  <Td>
                    <div className="flex flex-wrap gap-1">
                      {r.roles.filter(isStaffRole).map((role) => (
                        <Badge key={role} family="progress">
                          {ROLE_LABELS[role]}
                        </Badge>
                      ))}
                      {r.is_signatory ? <Badge family="attention">{t("roles.signatory")}</Badge> : null}
                    </div>
                  </Td>
                  <Td>
                    <StatusBadge status={r.status} label={t(`staff.status.${r.status}`)} />
                  </Td>
                  <Td className="text-muted">{r.last_seen_at ? formatRelative(r.last_seen_at) : t("staff.never")}</Td>
                  <Td>
                    <StaffRowActions
                      userId={r.user_id}
                      name={r.full_name}
                      status={r.status}
                      isSelf={r.user_id === me.userId}
                      values={{
                        email: r.email,
                        fullName: r.full_name,
                        roles: r.roles.filter(isStaffRole),
                        isSignatory: r.is_signatory,
                        designation: r.signatory_designation ?? "",
                      }}
                    />
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        </Card>
      ) : null}
    </>
  );
}
