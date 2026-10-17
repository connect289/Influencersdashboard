import { getTranslations } from "next-intl/server";
import { RequestQueue, type PlannedRequest } from "@/components/privacy/request-queue";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadDeletionFacts, loadPrivacyRequests } from "@/lib/privacy/data";
import { deletionPlan } from "@/lib/privacy/plan";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("privacy.staff.title") };
}

/** DPDP requests (spec 16): open deletion requests with what a deletion would erase and keep, and every request. */
export default async function PrivacyRequestsPage() {
  const { supabase } = await requireStaff("privacy.manage");
  const t = await getTranslations();
  const rows = await loadPrivacyRequests(supabase).catch(() => null);
  const planned: PlannedRequest[] | null = rows
    ? await Promise.all(
        rows.map(async (r) => {
          if (r.kind !== "deletion" || r.status !== "requested") return { ...r, plan: null };
          const f = await loadDeletionFacts(supabase, r.id);
          return {
            ...r,
            plan: f ? { ...deletionPlan(f), open_deals: f.open_deals, balance_paise: f.balance_paise } : null,
          };
        }),
      )
    : null;
  return (
    <>
      <PageHeader
        title={t("privacy.staff.title")}
        description={t("privacy.staff.subtitle")}
        help="/admin/help/super-admin#privacy-requests"
      />
      {planned ? (
        <RequestQueue rows={planned} />
      ) : (
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      )}
    </>
  );
}
