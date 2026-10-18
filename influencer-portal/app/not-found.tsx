import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { Button } from "@/components/ui/button";

export default async function NotFound() {
  const t = await getTranslations();
  return (
    <main className="flex min-h-dvh flex-col items-center justify-center gap-3 px-4 text-center">
      <p className="text-5xl font-bold text-primary">404</p>
      <h1 className="text-xl font-semibold">{t("errors.notFoundTitle")}</h1>
      <p className="max-w-sm text-sm text-muted">{t("errors.notFoundBody")}</p>
      <Button asChild variant="secondary">
        <Link href="/">{t("errors.goHome")}</Link>
      </Button>
    </main>
  );
}
