import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { AccountPage } from "@/components/account/account-page";
import { requireCreator } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("account.title") };
}

export default async function CreatorAccount() {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  return (
    <AccountPage
      supabase={supabase}
      name={me.displayName}
      email={me.email}
      showDevices={false}
      extra={
        <>
          <div>
            <dt className="text-muted">{t("account.handle")}</dt>
            <dd className="font-medium">@{me.handle}</dd>
          </div>
          <div>
            <dt className="text-muted">{t("privacy.title")}</dt>
            <dd>
              <Link href="/creator/account/privacy" className="font-medium text-primary underline underline-offset-2">
                {t("privacy.open")}
              </Link>
            </dd>
          </div>
        </>
      }
    />
  );
}
