"use client";
import {
  flexRender,
  getCoreRowModel,
  useReactTable,
  type ColumnDef,
  type RowSelectionState,
} from "@tanstack/react-table";
import { ArrowDown, ArrowUp, ChevronLeft, ChevronRight } from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useMemo, useState } from "react";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { bulkCreators } from "@/lib/actions/creators";
import { inviteCreators } from "@/lib/actions/onboarding";
import {
  creatorFiltersToQuery,
  PAGE_SIZES,
  PIPELINE_STAGES,
  type CreatorFilters,
  type CreatorListRow,
  type PipelineStage,
} from "@/lib/creators/crm";
import { formatCompact, formatDate, formatRelative } from "@/lib/format";
import { cn } from "@/lib/utils";
import type { Option } from "./creator-filters";

type BulkKind = "tag_add" | "tag_remove" | "owner" | "stage";

/** Server-paginated creators table: sorting and paging are links (URL state); rows can be selected for bulk actions. */
export function CreatorsTable({
  rows,
  total,
  filters,
  owners,
  canWrite,
  canInvite = false,
}: {
  rows: CreatorListRow[];
  total: number;
  filters: CreatorFilters;
  owners: Option[];
  canWrite: boolean;
  canInvite?: boolean;
}) {
  const t = useTranslations();
  const path = usePathname();
  const router = useRouter();
  const [selection, setSelection] = useState<RowSelectionState>({});
  const [bulk, setBulk] = useState<BulkKind | null>(null);
  const [value, setValue] = useState("");
  const { pending, run } = useAction();
  const page = filters.page ?? 1;
  const size = filters.page_size ?? 25;
  const pages = Math.max(1, Math.ceil(total / size));
  const href = (patch: Partial<CreatorFilters>) => `${path}?${creatorFiltersToQuery({ ...filters, ...patch })}`;
  const sortHref = (key: NonNullable<CreatorFilters["sort"]>) =>
    href({ sort: key, dir: filters.sort === key && filters.dir !== "desc" ? "desc" : "asc", page: undefined });

  const columns = useMemo<ColumnDef<CreatorListRow>[]>(() => {
    const sortable = (key: NonNullable<CreatorFilters["sort"]>, label: string) => {
      const active = filters.sort === key;
      return (
        <Link href={sortHref(key)} className="inline-flex items-center gap-1 hover:text-ink" scroll={false}>
          {label}
          {active ? filters.dir === "desc" ? <ArrowDown className="size-3" /> : <ArrowUp className="size-3" /> : null}
          <span className="sr-only">{t("creators.table.sortBy", { column: label })}</span>
        </Link>
      );
    };
    const cols: ColumnDef<CreatorListRow>[] = [
      {
        id: "name",
        header: () => sortable("name", t("creators.table.creator")),
        cell: ({ row }) => (
          <div className="min-w-0">
            <Link href={`/admin/creators/${row.original.id}`} className="font-medium text-primary hover:underline">
              {row.original.display_name}
            </Link>
            <span className="block text-xs text-muted">
              @{row.original.handle}
              {row.original.city ? ` · ${row.original.city}` : ""}
            </span>
            {row.original.tags.length ? (
              <span className="mt-1 flex flex-wrap gap-1">
                {row.original.tags.slice(0, 3).map((tag) => (
                  <Badge key={tag}>{tag}</Badge>
                ))}
              </span>
            ) : null}
          </div>
        ),
      },
      {
        id: "stage",
        header: () => sortable("stage", t("creators.table.stage")),
        cell: ({ row }) => (
          <span className="flex flex-col items-start gap-1">
            <StatusBadge
              status={row.original.pipeline_stage}
              label={t(`creators.stages.${row.original.pipeline_stage as PipelineStage}`)}
            />
            {row.original.is_blocked ? <Badge family="problem">{t("creators.statuses.blocked")}</Badge> : null}
          </span>
        ),
      },
      {
        id: "followers",
        header: () => sortable("followers", t("creators.table.followers")),
        cell: ({ row }) => (
          <span className="tabular-nums">
            {row.original.followers ? formatCompact(row.original.followers) : "—"}
            <span className="block text-xs text-muted">
              {row.original.platforms.map((p) => t(`platforms.${p as "instagram"}`)).join(", ")}
            </span>
          </span>
        ),
      },
      { id: "owner", header: () => t("creators.fields.owner"), cell: ({ row }) => row.original.owner_name ?? "—" },
      {
        id: "follow_up",
        header: () => sortable("follow_up", t("creators.table.followUp")),
        cell: ({ row }) => {
          const at = row.original.next_follow_up_at;
          if (!at) return "—";
          const overdue = new Date(at) < new Date();
          return <span className={cn(overdue && "font-medium text-danger")}>{formatDate(at)}</span>;
        },
      },
      {
        id: "last_activity",
        header: () => sortable("last_activity", t("creators.table.lastActivity")),
        cell: ({ row }) => (row.original.last_activity_at ? formatRelative(row.original.last_activity_at) : "—"),
      },
    ];
    if (canWrite)
      cols.unshift({
        id: "select",
        header: ({ table }) => (
          <input
            type="checkbox"
            className="size-4 accent-[var(--primary)]"
            aria-label={t("creators.table.selectAll")}
            checked={table.getIsAllRowsSelected()}
            ref={(el) => {
              if (el) el.indeterminate = table.getIsSomeRowsSelected();
            }}
            onChange={table.getToggleAllRowsSelectedHandler()}
          />
        ),
        cell: ({ row }) => (
          <input
            type="checkbox"
            className="size-4 accent-[var(--primary)]"
            aria-label={t("creators.table.select", { name: row.original.display_name })}
            checked={row.getIsSelected()}
            onChange={row.getToggleSelectedHandler()}
          />
        ),
      });
    return cols;
    // eslint-disable-next-line react-hooks/exhaustive-deps -- rebuilt when the URL state changes
  }, [filters, canWrite, t]);

  // TanStack Table returns non-memoisable functions; React Compiler skips this component, which is expected.
  // eslint-disable-next-line react-hooks/incompatible-library
  const table = useReactTable({
    data: rows,
    columns,
    getRowId: (r) => r.id,
    state: { rowSelection: selection },
    onRowSelectionChange: setSelection,
    getCoreRowModel: getCoreRowModel(),
    manualPagination: true,
    manualSorting: true,
  });
  const selectedIds = Object.keys(selection).filter((k) => selection[k]);

  return (
    <div>
      {selectedIds.length ? (
        <div
          className="mb-3 flex flex-wrap items-center gap-2 rounded-xl bg-primary-soft px-3 py-2 text-sm"
          role="region"
          aria-label={t("creators.bulk.title")}
        >
          <span className="font-medium text-primary">{t("creators.bulk.selected", { count: selectedIds.length })}</span>
          {(["tag_add", "tag_remove", "owner", "stage"] as const).map((k) => (
            <Button
              key={k}
              size="sm"
              variant="secondary"
              onClick={() => {
                setBulk(k);
                setValue(k === "stage" ? "contacted" : k === "owner" ? (owners[0]?.id ?? "") : "");
              }}
            >
              {t(`creators.bulk.${k}`)}
            </Button>
          ))}
          {canInvite ? (
            <Button
              size="sm"
              variant="secondary"
              disabled={pending}
              onClick={() =>
                run(
                  () => inviteCreators(selectedIds),
                  () => setSelection({}),
                )
              }
            >
              {t("onboarding.invite.bulk")}
            </Button>
          ) : null}
          <Button size="sm" variant="ghost" onClick={() => setSelection({})}>
            {t("common.clear")}
          </Button>
        </div>
      ) : null}
      <div className="-mx-4 overflow-x-auto md:mx-0">
        <table className="w-full min-w-[760px] border-collapse text-sm">
          <thead>
            {table.getHeaderGroups().map((hg) => (
              <tr key={hg.id}>
                {hg.headers.map((h) => (
                  <th
                    key={h.id}
                    scope="col"
                    className={cn(
                      "border-b border-line bg-surface px-3 py-2 text-left text-xs font-medium text-muted",
                      h.id === "select" && "w-10",
                    )}
                  >
                    {flexRender(h.column.columnDef.header, h.getContext())}
                  </th>
                ))}
              </tr>
            ))}
          </thead>
          <tbody>
            {table.getRowModel().rows.map((r) => (
              <tr key={r.id} className={cn(r.getIsSelected() && "bg-primary-soft/40")}>
                {r.getVisibleCells().map((c) => (
                  <td key={c.id} className="border-b border-line px-3 py-2.5 align-top">
                    {flexRender(c.column.columnDef.cell, c.getContext())}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <nav
        className="mt-3 flex flex-wrap items-center justify-between gap-2 text-sm"
        aria-label={t("creators.table.pagination")}
      >
        <span className="text-muted">
          {t("creators.table.showing", {
            from: total === 0 ? 0 : (page - 1) * size + 1,
            to: Math.min(page * size, total),
            total,
          })}
        </span>
        <div className="flex items-center gap-2">
          <label className="flex items-center gap-1 text-muted">
            {t("creators.table.perPage")}
            <select
              className="rounded-lg bg-surface px-2 py-1 ring-1 ring-line-strong ring-inset"
              value={size}
              onChange={(e) => {
                router.push(href({ page_size: Number(e.target.value), page: undefined }), { scroll: false });
              }}
            >
              {PAGE_SIZES.map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </select>
          </label>
          {page > 1 ? (
            <Button asChild variant="secondary" size="sm">
              <Link href={href({ page: page - 1 })} scroll={false} aria-label={t("creators.table.prev")}>
                <ChevronLeft />
              </Link>
            </Button>
          ) : null}
          <span className="tabular-nums">{t("creators.table.pageOf", { page, pages })}</span>
          {page < pages ? (
            <Button asChild variant="secondary" size="sm">
              <Link href={href({ page: page + 1 })} scroll={false} aria-label={t("creators.table.next")}>
                <ChevronRight />
              </Link>
            </Button>
          ) : null}
        </div>
      </nav>
      <Dialog open={bulk !== null} onOpenChange={(o) => !o && setBulk(null)}>
        {bulk ? (
          <DialogContent
            title={t(`creators.bulk.${bulk}`)}
            description={t("creators.bulk.applyTo", { count: selectedIds.length })}
            closeLabel={t("common.close")}
          >
            <form
              className="flex flex-col gap-4"
              onSubmit={(e) => {
                e.preventDefault();
                run(
                  () => bulkCreators(selectedIds, { action: bulk, value } as Parameters<typeof bulkCreators>[1]),
                  () => {
                    setBulk(null);
                    setSelection({});
                  },
                );
              }}
            >
              {bulk === "owner" ? (
                <Field id="bulk-owner" label={t("creators.fields.owner")}>
                  <Select id="bulk-owner" value={value} onChange={(e) => setValue(e.target.value)}>
                    {owners.map((o) => (
                      <option key={o.id} value={o.id}>
                        {o.name}
                      </option>
                    ))}
                  </Select>
                </Field>
              ) : bulk === "stage" ? (
                <Field id="bulk-stage" label={t("creators.table.stage")}>
                  <Select id="bulk-stage" value={value} onChange={(e) => setValue(e.target.value)}>
                    {PIPELINE_STAGES.map((s) => (
                      <option key={s} value={s}>
                        {t(`creators.stages.${s}`)}
                      </option>
                    ))}
                  </Select>
                </Field>
              ) : (
                <Field id="bulk-tag" label={t("creators.filters.tag")}>
                  <Input
                    id="bulk-tag"
                    value={value}
                    onChange={(e) => setValue(e.target.value)}
                    maxLength={40}
                    required
                  />
                </Field>
              )}
              <Button type="submit" disabled={pending || !value}>
                {t("common.apply")}
              </Button>
            </form>
          </DialogContent>
        ) : null}
      </Dialog>
    </div>
  );
}
