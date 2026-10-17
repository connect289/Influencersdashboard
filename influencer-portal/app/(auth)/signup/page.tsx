import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { CreatorSignUpForm } from "@/components/auth/forms";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("auth.signup.title") };
}

export default async function SignUpPage() {
  const t = await getTranslations();
  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className="text-xl font-semibold">{t("auth.signup.title")}</h1>
        <p className="mt-1 text-sm text-muted">{t("auth.signup.subtitle")}</p>
      </div>
      <CreatorSignUpForm termsHref="/legal/creator-terms" />
      <p className="text-center text-sm text-muted">
        {t("auth.signup.haveAccount")}{" "}
        <Link href="/login" className="font-medium text-primary underline-offset-4 hover:underline">
          {t("auth.signIn")}
        </Link>
      </p>
    </div>
  );
}
