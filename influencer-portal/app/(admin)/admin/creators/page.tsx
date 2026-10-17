import Link from "next/link";
import { Plus, Upload } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { CreatorDialog } from "@/components/creators/creator-dialog";
import { CreatorFilters } from "@/components/creators/creator-filters";
import { CreatorsKanban } from "@/components/creators/creators-kanban";
import { CreatorsTable } from "@/components/creators/creators-table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState, NoResults } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { activeFilterCount, creatorListResult, filtersToRpc, parseCreatorFilters } from "@/lib/creators/crm";
import { loadPickers, loadSavedViews } from "@/lib/creators/staff-data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.creators") };
}

export default async function CreatorsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { supabase, me } = await requireStaff("creator.read");
  const t = await getTranslations();
  const sp = await searchParams;
  const view = sp.view === "kanban" ? "kanban" : "table";
  const filters = parseCreatorFilters(sp);
  const rpc = filtersToRpc(filters);
  // The board shows up to 200 cards (most recently updated first); counts per stage are exact.
  const listArgs = view === "kanban" ? { ...rpc, page: 1, page_size: 200, sort: "updated", dir: "desc" } : rpc;
  const [list, counts, pickers, views] = await Promise.all([
    supabase.rpc("creator_list", { p: listArgs as never }),
    view === "kanban"
      ? supabase.rpc("creator_stage_counts", { p: rpc as never })
      : Promise.resolve({ data: [], error: null }),
    loadPickers(supabase),
    loadSavedViews(supabase, me.userId),
  ]);
  const parsed = list.error ? null : creatorListResult.safeParse(list.data);
  const result = parsed?.success ? parsed.data : null;
  const canWrite = me.permissions.has("creator.write");
  const filtered = activeFilterCount(filters) > 0 || Boolean(filters.q);
  const approvals = (await supabase.rpc("approvals_queue")).data?.length ?? 0;
  const actions = (
    <>
      <Button asChild variant="secondary">
        <Link href="/admin/creators/approvals">
          {t("onboarding.queue.title")}
          {approvals ? <Badge family="attention">{approvals}</Badge> : null}
        </Link>
      </Button>
      {me.permissions.has("creator.import") ? (
        <Button asChild variant="secondary">
          <Link href="/admin/creators/import">
            <Upload /> {t("creators.import.title")}
          </Link>
        </Button>
      ) : null}
      {canWrite ? (
        <CreatorDialog
          owners={pickers.owners}
          tiers={pickers.tiers}
          trigger={
            <Button>
              <Plus /> {t("creators.add")}
            </Button>
          }
        />
      ) : null}
    </>
  );
  return (
    <>
      <PageHeader
        title={t("nav.admin.creators")}
        description={result ? t("creators.count", { count: result.total }) : t("creators.subtitle")}
        actions={actions}
      />
      <CreatorFilters filters={filters} view={view} owners={pickers.owners} tiers={pickers.tiers} savedViews={views} />
      {!result ? (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      ) : result.total === 0 ? (
        filtered ? (
          <NoResults title={t("creators.noResults")} description={t("creators.noResultsHint")} />
        ) : (
          <EmptyState title={t("creators.empty")} description={t("creators.emptyHint")} />
        )
      ) : view === "kanban" ? (
        <CreatorsKanban
          rows={result.rows}
          counts={Object.fromEntries((counts.data ?? []).map((c) => [c.stage, c.n]))}
          canWrite={canWrite}
        />
      ) : (
        <Card className="p-0 md:p-0">
          <div className="p-4 md:p-5">
            <CreatorsTable
              rows={result.rows}
              total={result.total}
              filters={filters}
              owners={pickers.owners}
              canWrite={canWrite}
              canInvite={me.permissions.has("creator.import")}
            />
          </div>
        </Card>
      )}
    </>
  );
}
