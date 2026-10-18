import Link from "next/link";
import { Search } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { FinanceNav } from "@/components/finance/finance-nav";
import { AdjustmentDialog, HoldButton, HoldCreatorButtons } from "@/components/finance/ledger-actions";
import { LedgerTable } from "@/components/ledger/ledger-table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Select } from "@/components/ui/input";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { listLedger, parseLedgerFilters } from "@/lib/ledger/data";
import { ENTRY_STATUSES, LEDGER_TYPES } from "@/lib/ledger/lifecycle";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.finance") };
}

export default async function FinanceLedgerPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { supabase, me } = await requireStaff("ledger.read");
  const t = await getTranslations();
  const f = parseLedgerFilters(await searchParams);
  const canAdjust = me.permissions.has("ledger.adjust");
  const [list, creators] = await Promise.all([
    listLedger(supabase, f).catch(() => null),
    canAdjust
      ? supabase
          .from("creators")
          .select("id, display_name, handle")
          .not("status", "in", "(archived,blocked)")
          .order("display_name")
          .limit(1000)
          .then((r) => (r.data ?? []).map((c) => ({ id: c.id, name: `${c.display_name} (@${c.handle})` })))
      : Promise.resolve([]),
  ]);
  const pages = list ? Math.max(Math.ceil(list.total / 100), 1) : 1;
  const qs = (patch: Record<string, string | null>) => {
    const u = new URLSearchParams(
      Object.entries({ ...f, page: String(f.page) }).filter(
        (e): e is [string, string] => typeof e[1] === "string" && e[1] !== "",
      ),
    );
    for (const [k, v] of Object.entries(patch)) {
      if (v) u.set(k, v);
      else u.delete(k);
    }
    return `/admin/finance?${u.toString()}`;
  };
  return (
    <>
      <PageHeader
        title={t("nav.admin.finance")}
        description={t("finance.ledger.subtitle")}
        help="/admin/help/finance#ledger"
        actions={canAdjust ? <AdjustmentDialog creators={creators} creatorId={f.creator_id} /> : undefined}
      />
      <FinanceNav current="ledger" permissions={me.permissions} />
      <form method="get" action="/admin/finance" className="mb-3 flex flex-wrap gap-2" role="search">
        {f.creator_id ? <input type="hidden" name="creator_id" value={f.creator_id} /> : null}
        {f.deal_id ? <input type="hidden" name="deal_id" value={f.deal_id} /> : null}
        <label htmlFor="fl-q" className="sr-only">
          {t("finance.ledger.search")}
        </label>
        <Input
          id="fl-q"
          name="q"
          defaultValue={f.q ?? ""}
          placeholder={t("finance.ledger.search")}
          maxLength={60}
          className="min-w-48 flex-1"
        />
        <Select
          name="status"
          defaultValue={f.status ?? ""}
          aria-label={t("finance.ledger.columns.status")}
          className="w-auto"
        >
          <option value="">{t("finance.ledger.allStatuses")}</option>
          {ENTRY_STATUSES.map((s) => (
            <option key={s} value={s}>
              {t(`finance.statuses.${s}`)}
            </option>
          ))}
        </Select>
        <Select name="type" defaultValue={f.type ?? ""} aria-label={t("finance.ledger.type")} className="w-auto">
          <option value="">{t("finance.ledger.allTypes")}</option>
          {LEDGER_TYPES.map((x) => (
            <option key={x} value={x}>
              {t(`finance.types.${x}`)}
            </option>
          ))}
        </Select>
        <Input
          name="period"
          type="month"
          defaultValue={f.period ?? ""}
          aria-label={t("finance.ledger.period")}
          className="w-auto"
        />
        <Button type="submit" variant="secondary" aria-label={t("finance.ledger.search")}>
          <Search />
        </Button>
      </form>
      {f.creator_id && list?.rows[0] ? (
        <div className="mb-3 flex flex-wrap items-center gap-2 text-sm">
          <Badge>{list.rows[0].creator_name}</Badge>
          <Link href={qs({ creator_id: null, page: null })} className="text-primary hover:underline">
            {t("finance.ledger.allCreators")}
          </Link>
          {canAdjust ? <HoldCreatorButtons creatorId={f.creator_id} /> : null}
        </div>
      ) : null}
      <Card>
        {list === null ? (
          <ErrorState title={t("errors.loadFailed")} />
        ) : (
          <LedgerTable
            rows={list.rows}
            showCreator={!f.creator_id}
            creatorHref={(r) => qs({ creator_id: r.creator_id ?? null, page: null })}
            emptyTitle={t("finance.ledger.empty")}
            emptyHint={t("finance.ledger.emptyHint")}
            action={
              canAdjust
                ? (r) =>
                    ["accrued", "confirmed", "payable", "on_hold"].includes(r.status) &&
                    !["tds", "gst", "payout"].includes(r.type) ? (
                      <HoldButton entryId={r.id} held={r.held ?? false} />
                    ) : null
                : undefined
            }
          />
        )}
      </Card>
      {pages > 1 ? (
        <nav className="mt-3 flex items-center justify-between text-sm" aria-label={t("common.pagination")}>
          {f.page > 1 ? <Link href={qs({ page: String(f.page - 1) })}>{t("common.previous")}</Link> : <span />}
          <span className="text-muted">{t("contracts.pageOf", { page: f.page, pages })}</span>
          {f.page < pages ? <Link href={qs({ page: String(f.page + 1) })}>{t("common.next")}</Link> : <span />}
        </nav>
      ) : null}
    </>
  );
}
