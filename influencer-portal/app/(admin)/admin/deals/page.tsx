import Link from "next/link";
import { Plus, Search } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Select } from "@/components/ui/input";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { dealRowSchema } from "@/lib/deals/data";
import { DEAL_MODELS, DEAL_STATUSES, OPEN_STATUSES, type DealStatus } from "@/lib/deals/schemas";
import { formatDate } from "@/lib/format";
import { cn } from "@/lib/utils";

const PAGE_SIZE = 25;

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.deals") };
}

export default async function DealsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; model?: string; q?: string; page?: string }>;
}) {
  const { supabase, me } = await requireStaff("deal.read");
  const t = await getTranslations();
  const sp = await searchParams;
  const status = (DEAL_STATUSES as readonly string[]).includes(sp.status ?? "") ? (sp.status as DealStatus) : null;
  const model = (DEAL_MODELS as readonly string[]).includes(sp.model ?? "") ? (sp.model ?? "") : "";
  const q = (sp.q ?? "").slice(0, 80);
  const page = Math.max(Number.parseInt(sp.page ?? "1", 10) || 1, 1);
  const { data, error } = await supabase.rpc("deals_list", {
    p: { status: status ? [status] : [...OPEN_STATUSES], model: model ? [model] : [], q, page, page_size: PAGE_SIZE },
  });
  const parsed = z.object({ total: z.number(), rows: z.array(dealRowSchema) }).safeParse(data);
  const rows = parsed.success ? parsed.data.rows : [];
  const total = parsed.success ? parsed.data.total : 0;
  const params = (p: Record<string, string | number | null>) => {
    const u = new URLSearchParams();
    const merged = { status, model, q, page, ...p };
    for (const [k, v] of Object.entries(merged))
      if (v !== null && v !== "" && !(k === "page" && v === 1)) u.set(k, String(v));
    const s = u.toString();
    return s ? `/admin/deals?${s}` : "/admin/deals";
  };
  const tabs: (DealStatus | null)[] = [null, ...DEAL_STATUSES];
  return (
    <>
      <PageHeader
        title={t("nav.admin.deals")}
        description={t("deals.subtitle")}
        help="/admin/help/influencer-manager#deals"
        actions={
          <div className="flex gap-2">
            <Button asChild variant="secondary">
              <Link href="/admin/deals/presets">{t("deals.presets.title")}</Link>
            </Button>
            {me.permissions.has("deal.write") ? (
              <Button asChild>
                <Link href="/admin/deals/new">
                  <Plus /> {t("deals.new.button")}
                </Link>
              </Button>
            ) : null}
          </div>
        }
      />
      <nav
        className="-mx-4 mb-3 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0"
        aria-label={t("deals.filterByStatus")}
      >
        {tabs.map((s) => (
          <Link
            key={s ?? "open"}
            href={params({ status: s, page: 1 })}
            aria-current={status === s ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
              status === s ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {s ? t(`deals.statuses.${s}`) : t("deals.allOpen")}
          </Link>
        ))}
      </nav>
      <form className="mb-4 flex flex-wrap gap-2" action="/admin/deals">
        {status ? <input type="hidden" name="status" value={status} /> : null}
        <div className="relative min-w-48 flex-1">
          <Search
            className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-faint"
            aria-hidden
          />
          <Input
            name="q"
            defaultValue={q}
            placeholder={t("deals.search")}
            aria-label={t("deals.search")}
            className="pl-9"
            maxLength={80}
          />
        </div>
        <Select name="model" defaultValue={model} aria-label={t("deals.model")} className="w-auto">
          <option value="">{t("deals.allModels")}</option>
          {DEAL_MODELS.map((m) => (
            <option key={m} value={m}>
              {t(`deals.models.${m}`)}
            </option>
          ))}
        </Select>
        <Button type="submit" variant="secondary">
          {t("common.apply")}
        </Button>
      </form>
      <Card>
        {error || !parsed.success ? (
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        ) : null}
        {!error && parsed.success && rows.length === 0 ? (
          <EmptyState title={t("deals.empty")} description={t("deals.emptyHint")} />
        ) : null}
        {rows.length ? (
          <Table>
            <thead>
              <tr>
                <Th>{t("deals.table.deal")}</Th>
                <Th>{t("deals.table.creator")}</Th>
                <Th>{t("deals.table.status")}</Th>
                <Th>{t("deals.model")}</Th>
                <Th>{t("deals.table.dates")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((d) => (
                <tr key={d.id}>
                  <Td>
                    <Link href={`/admin/deals/${d.id}`} className="font-medium text-primary hover:underline">
                      {d.title}
                    </Link>
                    <span className="block text-xs text-muted">
                      {d.code}
                      {d.campaign_name ? ` · ${d.campaign_name}` : ""}
                    </span>
                  </Td>
                  <Td>
                    {d.creator_name}
                    <span className="block text-xs text-muted">@{d.handle}</span>
                  </Td>
                  <Td>
                    <div className="flex flex-wrap gap-1">
                      <StatusBadge status={d.status} label={t(`deals.statuses.${d.status}`)} />
                      {d.pending ? <Badge family="attention">{t("deals.awaitingCreator")}</Badge> : null}
                    </div>
                  </Td>
                  <Td>{t(`deals.models.${d.deal_model}`)}</Td>
                  <Td className="whitespace-nowrap">
                    {formatDate(d.starts_on)}
                    {d.ends_on ? ` – ${formatDate(d.ends_on)}` : ""}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        ) : null}
        {total > PAGE_SIZE ? (
          <nav className="mt-3 flex items-center justify-between text-sm" aria-label={t("common.pagination")}>
            <span className="text-muted">
              {t("deals.pageOf", { page, pages: Math.ceil(total / PAGE_SIZE), total })}
            </span>
            <div className="flex gap-2">
              {page > 1 ? (
                <Button asChild variant="secondary" size="sm">
                  <Link href={params({ page: page - 1 })}>{t("common.previous")}</Link>
                </Button>
              ) : null}
              {page * PAGE_SIZE < total ? (
                <Button asChild variant="secondary" size="sm">
                  <Link href={params({ page: page + 1 })}>{t("common.next")}</Link>
                </Button>
              ) : null}
            </div>
          </nav>
        ) : null}
      </Card>
    </>
  );
}
