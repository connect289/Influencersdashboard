import Link from "next/link";
import { Search } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { BriefsNav } from "@/components/content/briefs-nav";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState, NoResults } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { BRIEF_STATES, listBriefs, type BriefState } from "@/lib/content/data";
import { formatDate } from "@/lib/format";
import { cn } from "@/lib/utils";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.briefs") };
}

export default async function BriefsPage({ searchParams }: { searchParams: Promise<{ state?: string; q?: string }> }) {
  const { supabase } = await requireStaff("brief.read");
  const t = await getTranslations();
  const sp = await searchParams;
  const state = (BRIEF_STATES as readonly string[]).includes(sp.state ?? "") ? (sp.state as BriefState) : null;
  const q = (sp.q ?? "").slice(0, 80);
  const rows = await listBriefs(supabase, { q, state }).catch(() => null);
  const link = (s: BriefState | null) => {
    const u = new URLSearchParams();
    if (s) u.set("state", s);
    if (q) u.set("q", q);
    const x = u.toString();
    return x ? `/admin/briefs?${x}` : "/admin/briefs";
  };
  return (
    <>
      <PageHeader
        title={t("nav.admin.briefs")}
        description={t("content.briefs.subtitle")}
        help="/admin/help/influencer-manager#briefs"
      />
      <BriefsNav current="briefs" />
      <nav
        className="-mx-4 mb-3 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0"
        aria-label={t("content.briefs.filter")}
      >
        {([null, ...BRIEF_STATES] as (BriefState | null)[]).map((s) => (
          <Link
            key={s ?? "all"}
            href={link(s)}
            aria-current={state === s ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
              state === s ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {s ? t(`content.briefs.states.${s}`) : t("content.briefs.all")}
          </Link>
        ))}
      </nav>
      <form method="get" action="/admin/briefs" className="mb-3 flex gap-2" role="search">
        {state ? <input type="hidden" name="state" value={state} /> : null}
        <label htmlFor="br-q" className="sr-only">
          {t("content.briefs.search")}
        </label>
        <Input id="br-q" name="q" defaultValue={q} placeholder={t("content.briefs.searchPlaceholder")} maxLength={80} />
        <Button type="submit" variant="secondary" aria-label={t("content.briefs.search")}>
          <Search />
        </Button>
      </form>
      <Card>
        {rows === null ? (
          <ErrorState title={t("errors.loadFailed")} />
        ) : rows.length === 0 ? (
          q || state ? (
            <NoResults title={t("content.briefs.noResults")} />
          ) : (
            <EmptyState title={t("content.briefs.empty")} description={t("content.briefs.emptyHint")} />
          )
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("content.briefs.columns.deal")}</Th>
                <Th>{t("content.briefs.columns.creator")}</Th>
                <Th>{t("content.briefs.columns.version")}</Th>
                <Th>{t("content.briefs.columns.state")}</Th>
                <Th>{t("content.briefs.columns.updated")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <Td>
                    <Link href={`/admin/briefs/${r.id}`} className="font-medium text-primary hover:underline">
                      {r.deal_title}
                    </Link>
                    {r.deal_code ? <span className="block text-xs text-muted">{r.deal_code}</span> : null}
                  </Td>
                  <Td>
                    {r.creator_name}
                    {r.handle ? <span className="block text-xs text-muted">@{r.handle}</span> : null}
                  </Td>
                  <Td>{r.version ? t("content.briefs.versionN", { version: r.version }) : "—"}</Td>
                  <Td>
                    <span className="inline-flex flex-wrap gap-1">
                      <Badge family={r.version === null ? "neutral" : r.acknowledged ? "success" : "attention"}>
                        {t(
                          `content.briefs.states.${r.version === null ? "draft" : r.acknowledged ? "acknowledged" : "unacknowledged"}`,
                        )}
                      </Badge>
                      {r.open_questions ? (
                        <Badge family="attention">
                          {t("content.briefs.openQuestions", { count: r.open_questions })}
                        </Badge>
                      ) : null}
                    </span>
                  </Td>
                  <Td className="whitespace-nowrap">{formatDate(r.updated_at)}</Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </>
  );
}
