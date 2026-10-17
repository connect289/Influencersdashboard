import Link from "next/link";
import { LayoutGrid, List, Search } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { ContentNav, type ContentArea } from "@/components/content/content-nav";
import { DeliverableStatusBadge, NextStep } from "@/components/content/deliverable-bits";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState, NoResults } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { BOARD_COLUMNS, boardColumn } from "@/lib/content/board";
import {
  DELIVERABLE_VIEWS,
  listDeliverables,
  type DeliverableRow,
  type DeliverableView,
} from "@/lib/content/data";
import { cn } from "@/lib/utils";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.content") };
}

function Row({ r }: { r: DeliverableRow }) {
  return (
    <Link href={`/admin/content/${r.id}`} className="font-medium text-primary hover:underline">
      {r.title}
    </Link>
  );
}

export default async function ContentPage({
  searchParams,
}: {
  searchParams: Promise<{ view?: string; q?: string; layout?: string }>;
}) {
  const { supabase } = await requireStaff("deliverable.read");
  const t = await getTranslations();
  const sp = await searchParams;
  const view = (DELIVERABLE_VIEWS as readonly string[]).includes(sp.view ?? "")
    ? (sp.view as DeliverableView)
    : "open";
  const board = sp.layout === "board" && (view === "open" || view === "all");
  const q = (sp.q ?? "").slice(0, 80);
  const rows = await listDeliverables(supabase, { view, q }).catch(() => null);
  const area: ContentArea =
    view === "review"
      ? "review"
      : view === "overdue"
        ? "overdue"
        : view === "live"
          ? "live"
          : "deliverables";
  const href = (p: Record<string, string | null>) => {
    const u = new URLSearchParams();
    for (const [k, v] of Object.entries({
      view: view === "open" ? null : view,
      q: q || null,
      layout: board ? "board" : null,
      ...p,
    }))
      if (v) u.set(k, v);
    const s = u.toString();
    return s ? `/admin/content?${s}` : "/admin/content";
  };
  const emptyKey =
    view === "review"
      ? "emptyReview"
      : view === "overdue"
        ? "emptyOverdue"
        : view === "live"
          ? "emptyLive"
          : "empty";
  return (
    <>
      <PageHeader
        title={t("nav.admin.content")}
        description={t("content.subtitle")}
        help="/admin/help/content-reviewer#review"
      />
      <ContentNav current={area} />
      <div className="mb-3 flex flex-col gap-2 md:flex-row md:items-center">
        <form method="get" action="/admin/content" className="flex flex-1 gap-2" role="search">
          {view !== "open" ? <input type="hidden" name="view" value={view} /> : null}
          {board ? <input type="hidden" name="layout" value="board" /> : null}
          <label htmlFor="ct-q" className="sr-only">
            {t("content.search")}
          </label>
          <Input
            id="ct-q"
            name="q"
            defaultValue={q}
            placeholder={t("content.searchPlaceholder")}
            maxLength={80}
          />
          <Button type="submit" variant="secondary" aria-label={t("content.search")}>
            <Search />
          </Button>
        </form>
        {view === "open" || view === "all" ? (
          <div className="flex gap-1">
            <Button asChild size="sm" variant={board ? "ghost" : "secondary"}>
              <Link href={href({ layout: null })} aria-current={!board ? "page" : undefined}>
                <List /> {t("content.layout.list")}
              </Link>
            </Button>
            <Button asChild size="sm" variant={board ? "secondary" : "ghost"}>
              <Link href={href({ layout: "board" })} aria-current={board ? "page" : undefined}>
                <LayoutGrid /> {t("content.layout.board")}
              </Link>
            </Button>
            <Button asChild size="sm" variant="ghost">
              <Link href={href({ view: view === "all" ? null : "all" })}>
                {view === "all" ? t("content.openOnly") : t("content.includeClosed")}
              </Link>
            </Button>
          </div>
        ) : null}
      </div>
      {rows === null ? (
        <ErrorState title={t("errors.loadFailed")} />
      ) : rows.length === 0 ? (
        q ? (
          <NoResults title={t("content.noResults")} />
        ) : (
          <EmptyState title={t(`content.${emptyKey}`)} description={t("content.emptyHint")} />
        )
      ) : board ? (
        <div className="-mx-4 flex snap-x gap-3 overflow-x-auto px-4 pb-2 md:mx-0 md:px-0">
          {BOARD_COLUMNS.filter((c) => c !== "done" || view === "all").map((c) => {
            const items = rows.filter((r) => boardColumn(r.status, r.awaiting_verification) === c);
            return (
              <section
                key={c}
                className="w-72 shrink-0 snap-start rounded-[var(--radius-card)] bg-surface-2 p-2"
                aria-label={t(`content.board.${c}`)}
              >
                <h2 className="mb-2 flex items-center justify-between px-1 text-sm font-semibold">
                  {t(`content.board.${c}`)} <Badge>{items.length}</Badge>
                </h2>
                <ul className="flex flex-col gap-2">
                  {items.map((r) => (
                    <li
                      key={r.id}
                      className="rounded-xl bg-surface p-3 shadow-[var(--shadow-card)]"
                    >
                      <Row r={r} />
                      <p className="text-xs text-muted">
                        {r.creator_name} · {t(`platforms.${r.platform}`)}
                      </p>
                      <div className="mt-1">
                        <DeliverableStatusBadge status={r.status} overdueDays={r.overdue_days} />
                      </div>
                    </li>
                  ))}
                </ul>
              </section>
            );
          })}
        </div>
      ) : (
        <Card>
          <Table>
            <thead>
              <tr>
                <Th>{t("content.columns.deliverable")}</Th>
                <Th>{t("content.columns.creator")}</Th>
                <Th>{t("content.columns.status")}</Th>
                <Th>{t("content.columns.next")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className={cn(r.overdue_days ? "bg-danger-soft/40" : undefined)}>
                  <Td>
                    <Row r={r} />
                    <span className="block text-xs text-muted">
                      {r.code} · {t(`platforms.${r.platform}`)} · {t(`formats.${r.format}`)}
                    </span>
                  </Td>
                  <Td>
                    {r.creator_name}
                    <Link
                      href={`/admin/deals/${r.deal_id}?tab=content`}
                      className="block text-xs text-muted hover:underline"
                    >
                      {r.deal_title}
                    </Link>
                  </Td>
                  <Td>
                    <DeliverableStatusBadge status={r.status} overdueDays={r.overdue_days} />
                    {r.awaiting_verification ? (
                      <Badge family="attention" className="mt-1">
                        {t("content.awaitingVerification")}
                      </Badge>
                    ) : null}
                  </Td>
                  <Td>
                    <NextStep stage={r.pending_stage} due={r.due_dates} />
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        </Card>
      )}
    </>
  );
}
