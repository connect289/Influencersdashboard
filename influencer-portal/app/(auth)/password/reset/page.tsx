import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { PasswordLinkForm } from "@/components/auth/forms";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("auth.password.resetTitle") };
}

export default async function PasswordReset() {
  const t = await getTranslations();
  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className="text-xl font-semibold">{t("auth.password.resetTitle")}</h1>
        <p className="mt-1 text-sm text-muted">{t("auth.password.resetSubtitle")}</p>
      </div>
      <PasswordLinkForm />
      <Link
        href="/login/staff"
        className="text-center text-sm text-muted underline-offset-4 hover:underline"
      >
        {t("auth.backToSignIn")}
      </Link>
    </div>
  );
}
