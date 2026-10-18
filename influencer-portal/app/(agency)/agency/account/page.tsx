import { getTranslations } from "next-intl/server";
import { AccountPage } from "@/components/account/account-page";
import { requireAgency } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("account.title") };
}

export default async function AgencyAccount() {
  const { supabase, me } = await requireAgency();
  const t = await getTranslations();
  return (
    <AccountPage
      supabase={supabase}
      name={me.memberName}
      email={me.email}
      showDevices={false}
      extra={
        <div>
          <dt className="text-muted">{t("agencyPortal.agency")}</dt>
          <dd className="font-medium">{me.agencyName}</dd>
        </div>
      }
    />
  );
}
