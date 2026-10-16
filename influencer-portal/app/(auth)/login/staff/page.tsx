import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { StaffPasswordForm } from "@/components/auth/forms";
import { GoogleButton } from "@/components/auth/google-button";
import { Banner } from "@/components/ui/states";
import { googleEnabled } from "@/lib/env-public";
import { safeNext } from "@/lib/security";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("auth.staff.title") };
}

export default async function StaffLogin({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const t = await getTranslations();
  const sp = await searchParams;
  const next = safeNext(sp.next, "/admin");
  const notices: Record<string, string> = {
    idle: t("auth.reasons.idle"),
    revoked: t("auth.reasons.revoked"),
    link: t("auth.reasons.link"),
  };
  const errors: Record<string, string> = {
    oauth: t("auth.errors.googleFailed"),
    setup: t("auth.errors.setup"),
    domain: t("auth.errors.domain"),
  };
  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className="text-xl font-semibold">{t("auth.staff.title")}</h1>
        <p className="mt-1 text-sm text-muted">{t("auth.staff.subtitle")}</p>
      </div>
      {sp.reason && notices[sp.reason] ? <Banner tone="info">{notices[sp.reason]}</Banner> : null}
      {sp.error && errors[sp.error] ? <Banner tone="danger">{errors[sp.error]}</Banner> : null}
      {googleEnabled ? (
        <>
          <GoogleButton portal="staff" next={next} label={t("auth.google")} errorLabel={t("auth.errors.googleFailed")} hd={process.env.STAFF_GOOGLE_HD} />
          <div className="flex items-center gap-3 text-xs text-muted" aria-hidden>
            <span className="h-px flex-1 bg-line" />
            {t("auth.or")}
            <span className="h-px flex-1 bg-line" />
          </div>
        </>
      ) : null}
      <StaffPasswordForm next={next} />
      <div className="flex flex-col gap-2 text-center text-sm">
        <Link href="/password/reset" className="font-medium text-primary underline-offset-4 hover:underline">
          {t("auth.staff.firstTime")}
        </Link>
        <Link href="/login" className="text-muted underline-offset-4 hover:underline">
          {t("auth.staff.creatorLink")}
        </Link>
      </div>
    </div>
  );
}
