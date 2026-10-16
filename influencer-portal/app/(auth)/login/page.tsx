import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { CreatorEmailForm } from "@/components/auth/forms";
import { GoogleButton } from "@/components/auth/google-button";
import { Banner } from "@/components/ui/states";
import { googleEnabled } from "@/lib/env-public";
import { safeNext } from "@/lib/security";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("auth.creator.title") };
}

export default async function CreatorLogin({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const t = await getTranslations();
  const sp = await searchParams;
  const next = safeNext(sp.next, "/creator");
  const reason = sp.reason;
  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className="text-xl font-semibold">{t("auth.creator.title")}</h1>
        <p className="mt-1 text-sm text-muted">{t("auth.creator.subtitle")}</p>
      </div>
      {reason === "idle" ? <Banner tone="info">{t("auth.reasons.idle")}</Banner> : null}
      {reason === "revoked" ? <Banner tone="info">{t("auth.reasons.revoked")}</Banner> : null}
      {reason === "expired" ? <Banner tone="info">{t("auth.reasons.codeExpired")}</Banner> : null}
      {googleEnabled ? (
        <>
          <GoogleButton portal="creator" next={next} label={t("auth.google")} errorLabel={t("auth.errors.googleFailed")} />
          <div className="flex items-center gap-3 text-xs text-muted" aria-hidden>
            <span className="h-px flex-1 bg-line" />
            {t("auth.or")}
            <span className="h-px flex-1 bg-line" />
          </div>
        </>
      ) : null}
      <CreatorEmailForm next={next} />
      <p className="text-center text-sm text-muted">
        {t("auth.creator.staffPrompt")}{" "}
        <Link href="/login/staff" className="font-medium text-primary underline-offset-4 hover:underline">
          {t("auth.creator.staffLink")}
        </Link>
      </p>
    </div>
  );
}
