import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { Button } from "@/components/ui/button";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("auth.noAccess.title") };
}

export default async function NoAccess({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const t = await getTranslations();
  const creator = (await searchParams).portal === "creator";
  return (
    <div className="flex flex-col gap-4 text-center">
      <h1 className="text-xl font-semibold">{t("auth.noAccess.title")}</h1>
      <p className="text-sm text-muted">
        {creator ? t("auth.noAccess.creator") : t("auth.noAccess.staff")}
      </p>
      <form action="/auth/signout" method="post">
        <input type="hidden" name="to" value={creator ? "/login" : "/login/staff"} />
        <Button type="submit" variant="secondary" block>
          {t("auth.useAnother")}
        </Button>
      </form>
      <Link
        href={creator ? "/login" : "/login/staff"}
        className="text-sm text-muted underline-offset-4 hover:underline"
      >
        {t("auth.backToSignIn")}
      </Link>
    </div>
  );
}
