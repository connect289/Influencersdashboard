import { getTranslations } from "next-intl/server";
import { MembersCard } from "@/components/agency/members-card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireAgency } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.agency.team") };
}

export default async function AgencyTeamPage() {
  const { supabase, me } = await requireAgency();
  const t = await getTranslations();
  const { data, error } = await supabase
    .from("agency_members")
    .select("id, full_name, email, role, user_id")
    .eq("status", "active")
    .order("full_name");
  return (
    <>
      <PageHeader title={t("nav.agency.team")} description={t("agencyPortal.teamSubtitle")} />
      {error ? (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      ) : (
        <MembersCard
          agencyId={me.agencyId}
          members={data}
          canManage={me.isOwner}
          currentUserId={me.userId}
        />
      )}
    </>
  );
}
