import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { loadMyBriefs } from "@/lib/content/data";
import { formatDate } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.briefs") };
}

export default async function CreatorBriefsPage() {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  const rows = await loadMyBriefs(supabase, me.creatorId).catch(() => null);
  return (
    <>
      <PageHeader
        title={t("nav.creator.briefs")}
        description={t("content.my.briefsSubtitle")}
        help="/creator/help/creator#briefs"
      />
      {rows === null ? (
        <ErrorState title={t("errors.loadFailed")} />
      ) : rows.length === 0 ? (
        <EmptyState title={t("content.my.noBriefs")} description={t("content.my.noBriefsHint")} />
      ) : (
        <ul className="flex flex-col gap-2">
          {rows.map((b) => (
            <li key={b.id}>
              <Link
                href={`/creator/briefs/${b.id}`}
                className="flex items-center gap-3 rounded-[var(--radius-card)] bg-surface p-4 shadow-[var(--shadow-card)] hover:bg-surface-2"
              >
                <div className="min-w-0 flex-1">
                  <p className="font-medium">{b.deal_title}</p>
                  <p className="mt-1 flex flex-wrap items-center gap-2 text-sm text-muted">
                    <span>
                      {t("content.brief.versionLine", {
                        version: b.version,
                        date: formatDate(b.published_at),
                      })}
                    </span>
                    {b.acknowledged ? (
                      <Badge family="success">{t("content.briefs.states.acknowledged")}</Badge>
                    ) : (
                      <Badge family="attention">{t("content.my.readAndAcknowledge")}</Badge>
                    )}
                  </p>
                </div>
                <ChevronRight className="size-5 shrink-0 text-muted" aria-hidden />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
