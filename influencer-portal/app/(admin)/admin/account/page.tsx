import { getTranslations } from "next-intl/server";
import { AccountPage } from "@/components/account/account-page";
import { requireStaff } from "@/lib/auth/guards";
import { ROLE_LABELS } from "@/lib/auth/permissions";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("account.title") };
}

export default async function StaffAccount() {
  const { supabase, me } = await requireStaff();
  const t = await getTranslations();
  return (
    <AccountPage
      supabase={supabase}
      name={me.fullName}
      email={me.email}
      showDevices
      extra={
        <div>
          <dt className="text-muted">{t("account.roles")}</dt>
          <dd className="font-medium">
            {me.roles.map((r) => ROLE_LABELS[r]).join(", ")}
            {me.isSignatory ? ` · ${t("roles.signatory")}` : ""}
          </dd>
        </div>
      }
    />
  );
}
