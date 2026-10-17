import Link from "next/link";
import { BookOpen, Search } from "lucide-react";
import { useTranslations } from "next-intl";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { NoResults } from "@/components/ui/states";
import { searchGuides } from "@/lib/guides";
import type { Guide } from "@/lib/guides/types";

function GuideCards({ guides, base }: { guides: Guide[]; base: string }) {
  return (
    <ul className="grid gap-3 md:grid-cols-2">
      {guides.map((g) => (
        <li key={g.slug}>
          <Link
            href={`${base}/${g.slug}`}
            className="block h-full rounded-2xl bg-surface p-4 shadow-[var(--shadow-card)] hover:opacity-90"
          >
            <span className="flex items-center gap-2 font-semibold">
              <BookOpen className="size-4 text-primary" aria-hidden />
              {g.title}
            </span>
            <span className="mt-1 block text-sm text-muted">{g.summary}</span>
          </Link>
        </li>
      ))}
    </ul>
  );
}

/** The Help landing page: search across the reader's guides, then the guides themselves. */
export function HelpIndex({
  base,
  mine,
  others,
  q,
}: {
  base: string;
  mine: Guide[];
  others: Guide[];
  q: string;
}) {
  const t = useTranslations();
  const hits = q ? searchGuides([...mine, ...others], q) : [];
  return (
    <div className="flex flex-col gap-5">
      <form action={base} className="relative" role="search">
        <Search
          className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-faint"
          aria-hidden
        />
        <Input
          name="q"
          defaultValue={q}
          placeholder={t("help.search")}
          aria-label={t("help.search")}
          className="pl-9"
          maxLength={80}
        />
      </form>
      {q ? (
        hits.length ? (
          <Card>
            <h2 className="mb-2 text-sm font-semibold">{t("help.results", { q })}</h2>
            <ul className="flex flex-col divide-y divide-line">
              {hits.map((h) => (
                <li key={`${h.guide.slug}-${h.section.id}`} className="py-2">
                  <Link
                    href={`${base}/${h.guide.slug}#${h.section.id}`}
                    className="font-medium text-primary hover:underline"
                  >
                    {h.section.title}
                  </Link>
                  <span className="block text-xs text-muted">{h.guide.title}</span>
                </li>
              ))}
            </ul>
          </Card>
        ) : (
          <NoResults title={t("help.noResults")} description={t("help.noResultsHint")} />
        )
      ) : null}
      {mine.length ? (
        <section className="flex flex-col gap-2">
          {others.length ? (
            <h2 className="text-sm font-semibold text-muted">{t("help.forYou")}</h2>
          ) : null}
          <GuideCards guides={mine} base={base} />
        </section>
      ) : null}
      {others.length ? (
        <section className="flex flex-col gap-2">
          <h2 className="text-sm font-semibold text-muted">{t("help.otherRoles")}</h2>
          <GuideCards guides={others} base={base} />
        </section>
      ) : null}
    </div>
  );
}
