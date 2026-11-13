import Link from "next/link";
import { CircleCheck } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Logo } from "@/components/brand/logo";
import { Button } from "@/components/ui/button";
import { ErrorState } from "@/components/ui/states";
import { readUnsubscribeToken, tokenForPath } from "@/lib/notify/unsubscribe-run";

export const dynamic = "force-dynamic";

export async function generateMetadata() {
  const t = await getTranslations();
  return {
    title: t("unsubscribe.title"),
    robots: { index: false, follow: false },
    referrer: "no-referrer" as const,
  };
}

/**
 * Where the "Stop these emails" link in an email lands (D-198). Opening the page changes nothing, because mail
 * scanners open links: it names the kind of email and offers one button, a plain form POST that works without
 * JavaScript. Afterwards, and for a link that is not ours, it shows the same neutral result. Nothing about the
 * person is shown: the link carries no name or address, and the page reads nothing from the database.
 */
export default async function UnsubscribePage({
  params,
  searchParams,
}: {
  params: Promise<{ token: string }>;
  searchParams: Promise<{ r?: string | string[] }>;
}) {
  const [{ token }, { r }, t] = await Promise.all([params, searchParams, getTranslations()]);
  const claims = readUnsubscribeToken(token);
  const result = r === "done" || r === "limited" || r === "failed" ? r : null;
  const finished = result === "done" || !claims;

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md flex-col items-center justify-center gap-5 px-4 py-10 text-center">
      <Logo label={t("app.tagline")} />
      {finished ? (
        <>
          <CircleCheck className="size-10 text-success" aria-hidden />
          <h1 className="text-xl font-semibold">{t("unsubscribe.done.title")}</h1>
          <p className="text-sm text-muted">{t("unsubscribe.done.body")}</p>
          <p className="text-sm text-muted">{t("unsubscribe.required")}</p>
          <Link href="/" className="text-sm font-medium text-primary hover:underline">
            {t("unsubscribe.done.settings")}
          </Link>
        </>
      ) : (
        <>
          {result ? (
            <ErrorState
              title={t(result === "limited" ? "unsubscribe.limited.title" : "unsubscribe.failed.title")}
              description={t(result === "limited" ? "unsubscribe.limited.body" : "unsubscribe.failed.body")}
            />
          ) : null}
          <h1 className="text-xl font-semibold">{t("unsubscribe.confirm.title")}</h1>
          <p className="text-sm text-muted">{t("unsubscribe.confirm.body")}</p>
          <p className="font-semibold">{t(`unsubscribe.categories.${claims.category}`)}</p>
          <form method="post" action={`/unsubscribe/${tokenForPath(token)}/confirm`} className="w-full">
            <Button type="submit" size="lg" block>
              {t("unsubscribe.confirm.button")}
            </Button>
          </form>
          <p className="text-sm text-muted">{t("unsubscribe.required")}</p>
          <p className="text-sm text-muted">{t("unsubscribe.confirm.back")}</p>
        </>
      )}
    </main>
  );
}
