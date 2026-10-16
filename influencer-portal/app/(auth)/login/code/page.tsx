import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { CreatorCodeForm } from "@/components/auth/forms";
import { otpEmailHint } from "@/lib/auth/landing";
import { safeNext } from "@/lib/security";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("auth.code.title") };
}

export default async function CreatorCode({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const t = await getTranslations();
  const next = safeNext((await searchParams).next, "/creator");
  const hint = await otpEmailHint();
  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className="text-xl font-semibold">{t("auth.code.title")}</h1>
        <p className="mt-1 text-sm text-muted">{hint ? t("auth.code.subtitle", { email: hint }) : t("auth.code.subtitleNoEmail")}</p>
      </div>
      <CreatorCodeForm next={next} />
      <Link href={`/login?next=${encodeURIComponent(next)}`} className="text-center text-sm font-medium text-primary underline-offset-4 hover:underline">
        {t("auth.code.again")}
      </Link>
    </div>
  );
}
