import { getTranslations } from "next-intl/server";
import { Logo } from "@/components/brand/logo";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("links.inactive.title"), robots: { index: false } };
}

/** Where a retired or unknown short link lands. */
export default async function LinkInactivePage() {
  const t = await getTranslations();
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md flex-col items-center justify-center gap-4 px-4 text-center">
      <Logo label={t("app.tagline")} />
      <h1 className="text-xl font-semibold">{t("links.inactive.title")}</h1>
      <p className="text-sm text-muted">{t("links.inactive.body")}</p>
      <a href="https://eduwit.in" className="text-sm font-medium text-primary hover:underline">
        {t("links.inactive.cta")}
      </a>
    </main>
  );
}
