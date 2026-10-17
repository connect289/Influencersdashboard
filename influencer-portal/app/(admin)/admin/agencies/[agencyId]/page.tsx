import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { AgencyDialog } from "@/components/agency/agency-dialog";
import { AgencyStatusButton } from "@/components/agency/agency-status";
import { GrantBadges } from "@/components/agency/grant-badges";
import { LinkRequest } from "@/components/agency/link-request";
import { LinkRevoke } from "@/components/agency/link-revoke";
import { MembersCard } from "@/components/agency/members-card";
import { StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.agencies") };
}

export default async function AgencyDetailPage({
  params,
}: {
  params: Promise<{ agencyId: string }>;
}) {
  const { agencyId } = await params;
  if (!z.uuid().safeParse(agencyId).success) notFound();
  const { supabase } = await requireStaff("agency.manage");
  const t = await getTranslations();
  const [agency, members, links] = await Promise.all([
    supabase.from("agencies").select("*").eq("id", agencyId).maybeSingle(),
    supabase
      .from("agency_members")
      .select("id, full_name, email, role, user_id")
      .eq("agency_id", agencyId)
      .eq("status", "active")
      .order("full_name"),
    supabase
      .from("agency_creator_links")
      .select(
        "id, status, can_view, can_act_deliverables, can_negotiate_sign, can_view_earnings, creators(display_name, handle)",
      )
      .eq("agency_id", agencyId)
      .in("status", ["pending", "active"])
      .order("requested_at", { ascending: false }),
  ]);
  if (!agency.error && !agency.data) notFound();
  const a = agency.data;
  return (
    <>
      <Link
        href="/admin/agencies"
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.admin.agencies")}
      </Link>
      {!a || members.error || links.error ? (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      ) : (
        <>
          <PageHeader
            title={a.name}
            description={[a.legal_name, a.email, a.gstin].filter(Boolean).join(" · ") || undefined}
            actions={
              <>
                <StatusBadge
                  status={a.status}
                  label={t(`agencies.statuses.${a.status as "active" | "suspended"}`)}
                />
                <AgencyDialog
                  initial={{
                    id: a.id,
                    name: a.name,
                    legalName: a.legal_name ?? "",
                    email: a.email ?? "",
                    phone: a.phone_e164 ?? "",
                    gstin: a.gstin ?? "",
                    notes: a.notes ?? "",
                  }}
                  trigger={
                    <Button variant="secondary" size="sm">
                      {t("common.edit")}
                    </Button>
                  }
                />
                <AgencyStatusButton agencyId={a.id} status={a.status} name={a.name} />
              </>
            }
          />
          <div className="flex flex-col gap-4">
            <MembersCard agencyId={a.id} members={members.data} canManage />
            <Card>
              <CardHeader
                title={t("agencies.linkedCreators")}
                description={t("agencies.links.adminHint")}
              />
              <div className="mb-4">
                <LinkRequest agencyId={a.id} />
              </div>
              {links.data.length === 0 ? (
                <EmptyState title={t("agencies.links.empty")} />
              ) : (
                <ul className="flex flex-col divide-y divide-line">
                  {links.data.map((l) => (
                    <li key={l.id} className="flex flex-wrap items-center gap-3 py-3">
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-medium">{l.creators.display_name}</p>
                        <p className="text-xs text-muted">@{l.creators.handle}</p>
                        {l.status === "active" ? (
                          <div className="mt-1">
                            <GrantBadges grants={l} />
                          </div>
                        ) : null}
                      </div>
                      <StatusBadge
                        status={l.status}
                        label={t(`agencies.links.status.${l.status as "pending" | "active"}`)}
                      />
                      <LinkRevoke linkId={l.id} name={l.creators.display_name} />
                    </li>
                  ))}
                </ul>
              )}
            </Card>
          </div>
        </>
      )}
    </>
  );
}
