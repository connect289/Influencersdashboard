import { redirect } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { StaffCodeForms } from "@/components/auth/forms";
import { fetchMe } from "@/lib/auth/guards";
import { maskEmail } from "@/lib/auth/landing";
import { safeNext } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("auth.verify.title") };
}

export default async function Verify({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const t = await getTranslations();
  const next = safeNext((await searchParams).next, "/admin");
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  if (!data?.claims.sub) redirect(`/login/staff?next=${encodeURIComponent(next)}`);
  const me = await fetchMe(supabase);
  if (me.kind !== "staff") redirect("/no-access");
  if (me.session?.verified && !me.session.revoked) redirect(next);
  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className="text-xl font-semibold">{t("auth.verify.title")}</h1>
        <p className="mt-1 text-sm text-muted">
          {t("auth.verify.subtitle", { email: maskEmail(me.email ?? "") })}
        </p>
      </div>
      <StaffCodeForms next={next} />
      <form action="/auth/signout" method="post" className="text-center">
        <input type="hidden" name="to" value="/login/staff" />
        <button type="submit" className="text-sm text-muted underline-offset-4 hover:underline">
          {t("auth.useAnother")}
        </button>
      </form>
    </div>
  );
}
