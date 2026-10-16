import { redirect } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { NewPasswordForm } from "@/components/auth/forms";
import { PASSWORD_MIN } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("auth.password.newTitle") };
}

export default async function NewPassword() {
  const t = await getTranslations();
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  if (!data?.claims.sub) redirect("/login/staff?reason=link");
  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className="text-xl font-semibold">{t("auth.password.newTitle")}</h1>
        <p className="mt-1 text-sm text-muted">{t("auth.password.newSubtitle")}</p>
      </div>
      <NewPasswordForm min={PASSWORD_MIN} />
    </div>
  );
}
