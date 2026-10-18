import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { Logo } from "@/components/brand/logo";
import { EmptyState } from "@/components/ui/states";
import { formatDate } from "@/lib/format";
import { adminClient } from "@/lib/supabase/admin";

export const revalidate = 300;

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("legal.title") };
}

/** Public: the current creator platform terms and privacy notice (linked from the sign-up form). */
export default async function CreatorTermsPage() {
  const t = await getTranslations();
  const { data } = await adminClient()
    .from("terms_versions")
    .select("kind, version, title, body, effective_at")
    .in("kind", ["platform_terms", "privacy"])
    .lte("effective_at", new Date().toISOString())
    .order("version", { ascending: false });
  const current = ["platform_terms", "privacy"]
    .map((k) => (data ?? []).find((d) => d.kind === k))
    .filter((d): d is NonNullable<typeof d> => Boolean(d));
  return (
    <main className="mx-auto w-full max-w-2xl px-4 py-8">
      <Link href="/signup" className="mb-6 inline-block">
        <Logo label={t("app.tagline")} />
      </Link>
      <h1 className="mb-6 text-2xl font-semibold">{t("legal.title")}</h1>
      {current.length === 0 ? (
        <EmptyState title={t("legal.empty")} description={t("legal.emptyHint")} />
      ) : (
        current.map((d) => (
          <article key={d.kind} className="mb-8">
            <h2 className="text-lg font-semibold">{d.title}</h2>
            <p className="mb-3 text-xs text-muted">
              {t("terms.version", { version: d.version, date: formatDate(d.effective_at) })}
            </p>
            <div className="text-sm leading-relaxed whitespace-pre-line">{d.body}</div>
          </article>
        ))
      )}
    </main>
  );
}
