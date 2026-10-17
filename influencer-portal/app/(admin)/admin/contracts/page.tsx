import Link from "next/link";
import { Search } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { ContractsNav } from "@/components/contracts/contracts-nav";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import {
  CONTRACT_STATUSES,
  contractRowSchema,
  OPEN_CONTRACT_STATUSES,
  type ContractStatus,
} from "@/lib/contracts/data";
import { formatDate } from "@/lib/format";
import { cn } from "@/lib/utils";

const PAGE_SIZE = 25;

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.contracts") };
}

export default async function ContractsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; q?: string; page?: string }>;
}) {
  const { supabase } = await requireStaff("contract.read");
  const t = await getTranslations();
  const sp = await searchParams;
  const status = (CONTRACT_STATUSES as readonly string[]).includes(sp.status ?? "")
    ? (sp.status as ContractStatus)
    : null;
  const q = (sp.q ?? "").slice(0, 80);
  const page = Math.max(Number.parseInt(sp.page ?? "1", 10) || 1, 1);
  const { data, error } = await supabase.rpc("contracts_list", {
    p: { status: status ? [status] : [...OPEN_CONTRACT_STATUSES], q, page, page_size: PAGE_SIZE },
  });
  const parsed = z.object({ total: z.number(), rows: z.array(contractRowSchema) }).safeParse(data);
  const rows = parsed.success ? parsed.data.rows : [];
  const total = parsed.success ? parsed.data.total : 0;
  const link = (p: Record<string, string | number | null>) => {
    const u = new URLSearchParams();
    for (const [k, v] of Object.entries({ status, q, page, ...p }))
      if (v !== null && v !== "" && !(k === "page" && v === 1)) u.set(k, String(v));
    const s = u.toString();
    return s ? `/admin/contracts?${s}` : "/admin/contracts";
  };
  const pages = Math.max(Math.ceil(total / PAGE_SIZE), 1);
  return (
    <>
      <PageHeader
        title={t("nav.admin.contracts")}
        description={t("contracts.subtitle")}
        help="/admin/help/influencer-manager#contracts"
      />
      <ContractsNav current="contracts" />
      <nav
        className="-mx-4 mb-3 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0"
        aria-label={t("contracts.filterByStatus")}
      >
        {([null, ...CONTRACT_STATUSES] as (ContractStatus | null)[]).map((s) => (
          <Link
            key={s ?? "open"}
            href={link({ status: s, page: 1 })}
            aria-current={status === s ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
              status === s
                ? "bg-primary-soft font-medium text-primary"
                : "text-muted hover:bg-surface-2",
            )}
          >
            {s ? t(`contracts.statuses.${s}`) : t("contracts.openOnly")}
          </Link>
        ))}
      </nav>
      <form method="get" action="/admin/contracts" className="mb-3 flex gap-2" role="search">
        {status ? <input type="hidden" name="status" value={status} /> : null}
        <label htmlFor="ct-q" className="sr-only">
          {t("contracts.search")}
        </label>
        <Input
          id="ct-q"
          name="q"
          defaultValue={q}
          placeholder={t("contracts.searchPlaceholder")}
          maxLength={80}
        />
        <Button type="submit" variant="secondary" aria-label={t("contracts.search")}>
          <Search />
        </Button>
      </form>
      <Card>
        {error || !parsed.success ? (
          <ErrorState title={t("errors.loadFailed")} />
        ) : rows.length === 0 ? (
          <EmptyState
            title={q || status ? t("contracts.noResults") : t("contracts.empty")}
            description={t("contracts.emptyHint")}
          />
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("contracts.columns.number")}</Th>
                <Th>{t("contracts.columns.creator")}</Th>
                <Th>{t("contracts.columns.deal")}</Th>
                <Th>{t("contracts.columns.status")}</Th>
                <Th>{t("contracts.columns.updated")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <Td>
                    <Link
                      href={`/admin/contracts/${r.id}`}
                      className="font-medium text-primary hover:underline"
                    >
                      {r.number}
                    </Link>
                    {r.kind !== "original" ? (
                      <Badge className="ml-2">
                        {t(`contracts.kinds.${r.kind as "amendment"}`)}
                      </Badge>
                    ) : null}
                  </Td>
                  <Td>
                    {r.creator_name}
                    {r.handle ? (
                      <span className="block text-xs text-muted">@{r.handle}</span>
                    ) : null}
                  </Td>
                  <Td>
                    <Link href={`/admin/deals/${r.deal_id}`} className="hover:underline">
                      {r.deal_title}
                    </Link>
                    {r.deal_code ? (
                      <span className="block text-xs text-muted">{r.deal_code}</span>
                    ) : null}
                  </Td>
                  <Td>
                    <StatusBadge status={r.status} label={t(`contracts.statuses.${r.status}`)} />
                    {r.pending_requests ? (
                      <Badge family="attention" className="ml-1">
                        {t("contracts.pendingCount", { count: r.pending_requests })}
                      </Badge>
                    ) : null}
                  </Td>
                  <Td className="whitespace-nowrap">{formatDate(r.updated_at)}</Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
      {pages > 1 ? (
        <nav
          className="mt-3 flex items-center justify-between text-sm"
          aria-label={t("common.pagination")}
        >
          {page > 1 ? (
            <Link href={link({ page: page - 1 })}>{t("common.previous")}</Link>
          ) : (
            <span />
          )}
          <span className="text-muted">{t("contracts.pageOf", { page, pages })}</span>
          {page < pages ? (
            <Link href={link({ page: page + 1 })}>{t("common.next")}</Link>
          ) : (
            <span />
          )}
        </nav>
      ) : null}
    </>
  );
}
