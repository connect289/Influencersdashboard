"use client";
import { useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowDown, ArrowUp, ArrowUpDown, BellOff, FlaskConical, LoaderCircle, RotateCcw, Send, Trash2, X } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import { formatDateTime, relativeTime } from "@/lib/format";
import { DESTINATION_LABEL, formatPhone, humanize, leadsHref, statusTone, type LeadPage, type LeadQuery, type LeadRow, type Sort } from "@/lib/leads";
import { loadMoreLeads } from "./actions";
import { DeleteDialog, useRestore } from "./LeadMutations";
import { PassToCrmDialog } from "./PassToCrm";
import { NOT_PASSED_LABEL } from "@/lib/routing";

function SortHeader({ query, sort, children, className }: { query: LeadQuery; sort: Sort; children: React.ReactNode; className?: string }) {
  const active = query.sort === sort;
  const dir = active ? (query.dir === "desc" ? "asc" : "desc") : sort === "name" ? "asc" : "desc";
  const Icon = !active ? ArrowUpDown : query.dir === "desc" ? ArrowDown : ArrowUp;
  return (
    <th scope="col" aria-sort={active ? (query.dir === "desc" ? "descending" : "ascending") : undefined} className={cn("px-3 py-2.5 font-medium", className)}>
      <Link href={leadsHref(query, { sort, dir })} scroll={false} className={cn("inline-flex items-center gap-1 hover:text-fg", active && "text-fg")}>
        {children} <Icon className={cn("size-3", !active && "opacity-40")} aria-hidden />
      </Link>
    </th>
  );
}

function Routing({ row }: { row: LeadRow }) {
  if (row.not_passed) return <Badge tone="danger" className="whitespace-nowrap">Not passed · {NOT_PASSED_LABEL[row.not_passed.reason] ?? row.not_passed.reason}</Badge>;
  if (!row.destination_type) return <span className="text-subtle">Not routed</span>;
  if (row.destination_type === "partner") return <Badge tone="brand">Partner{row.partner_id ? ` #${row.partner_id}` : ""}</Badge>;
  return <Badge tone="info">{DESTINATION_LABEL[row.destination_type] ?? humanize(row.destination_type)}</Badge>;
}

/** The lead list. Rows after the first page load in place (keyset paging), so selection survives "Load more". */
export function LeadsTable({ search, query, initial, openId }: { search: string; query: LeadQuery; initial: LeadPage; openId: number | null }) {
  const router = useRouter();
  const [rows, setRows] = useState(initial.rows);
  const [next, setNext] = useState(initial.next);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [loading, startLoad] = useTransition();
  const [deleting, setDeleting] = useState(false);
  const [passing, setPassing] = useState(false);

  const removeRows = (ids: number[]) => {
    if (!ids.length) return;
    const gone = new Set(ids);
    setRows((r) => r.filter((x) => !gone.has(x.id)));
    setSelected((s) => new Set([...s].filter((id) => !gone.has(id))));
    router.refresh(); // counts and facets
  };
  const { restore, pending: restoring } = useRestore(removeRows);

  const allSelected = rows.length > 0 && rows.every((r) => selected.has(r.id));
  const toggleAll = () => setSelected(allSelected ? new Set() : new Set(rows.map((r) => r.id)));
  const toggleOne = (id: number) =>
    setSelected((s) => {
      const n = new Set(s);
      if (n.has(id)) n.delete(id); else n.add(id);
      return n;
    });

  const loadMore = () => {
    if (!next) return;
    startLoad(async () => {
      try {
        const page = await loadMoreLeads(search, next);
        setRows((r) => {
          const have = new Set(r.map((x) => x.id));
          return [...r, ...page.rows.filter((x) => !have.has(x.id))];
        });
        setNext(page.next);
      } catch {
        toast.error("Could not load more leads. Try again.");
      }
    });
  };

  const ids = [...selected];
  const partnerCount = rows.filter((r) => selected.has(r.id) && r.destination_type === "partner").length;
  const passable = !query.bin && ids.length > 0 && rows.filter((r) => selected.has(r.id)).every((r) => r.not_passed);

  return (
    <>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[960px] text-left text-[13px]">
          <thead className="text-[11px] uppercase tracking-wider text-subtle">
            <tr className="border-b border-border">
              <th scope="col" className="w-10 py-2.5 pl-4 pr-1">
                <input type="checkbox" aria-label="Select all shown leads" checked={allSelected} onChange={toggleAll} className="size-4 cursor-pointer accent-[var(--primary)] align-middle" />
              </th>
              <SortHeader query={query} sort="name">Lead</SortHeader>
              <th scope="col" className="px-3 py-2.5 font-medium">Interested in</th>
              <th scope="col" className="px-3 py-2.5 font-medium">Status</th>
              <th scope="col" className="px-3 py-2.5 font-medium">Stage</th>
              <th scope="col" className="px-3 py-2.5 font-medium">Source</th>
              <th scope="col" className="px-3 py-2.5 font-medium">Routing</th>
              <SortHeader query={query} sort="created_at">Created</SortHeader>
              {query.bin
                ? <th scope="col" className="py-2.5 pl-3 pr-4 font-medium">Deleted</th>
                : <SortHeader query={query} sort="last_activity" className="pr-4">Last activity</SortHeader>}
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {rows.map((r) => {
              const href = leadsHref(query, {}, r.id);
              const isOpen = openId === r.id;
              const isSel = selected.has(r.id);
              return (
                <tr
                  key={r.id}
                  onClick={(e) => { if (!(e.target as HTMLElement).closest("a, button, input, label")) router.push(href, { scroll: false }); }}
                  className={cn("cursor-pointer transition-colors hover:bg-surface-hover", isSel && "bg-amber/[0.06]", isOpen && "bg-surface-2")}
                >
                  <td className="w-10 py-2.5 pl-4 pr-1">
                    <input type="checkbox" aria-label={`Select lead ${r.id}`} checked={isSel} onChange={() => toggleOne(r.id)} className="size-4 cursor-pointer accent-[var(--primary)] align-middle" />
                  </td>
                  <td className="max-w-[240px] px-3 py-2.5">
                    <Link href={href} scroll={false} className="block truncate font-medium text-fg hover:underline">
                      {r.student_name?.trim() || <span className="text-subtle">Unnamed</span>}
                    </Link>
                    <span className="flex items-center gap-1.5 text-[12px] text-subtle">
                      <span className="tabular">{formatPhone(r.whatsapp_number)}</span>
                      {r.is_test && <FlaskConical className="size-3 text-amber" aria-label="Test lead" />}
                      {r.is_opted_out && <BellOff className="size-3 text-danger" aria-label="Opted out" />}
                    </span>
                  </td>
                  <td className="max-w-[220px] px-3 py-2.5">
                    <span className="block truncate text-fg">{r.interested_course || <span className="text-subtle">—</span>}</span>
                    {(r.interested_specialization || r.program_level) && (
                      <span className="block truncate text-[12px] text-subtle">{[r.interested_specialization, r.program_level && humanize(r.program_level)].filter(Boolean).join(" · ")}</span>
                    )}
                  </td>
                  <td className="px-3 py-2.5">
                    {r.lead_status ? <Badge tone={statusTone(r.lead_status)}>{humanize(r.lead_status)}</Badge> : <span className="text-subtle">—</span>}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2.5 text-muted">
                    {humanize(r.stage)}
                    {r.sub_stage && <span className="block text-[12px] text-subtle">{humanize(r.sub_stage)}</span>}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2.5 text-muted">{humanize(r.lead_source)}</td>
                  <td className="whitespace-nowrap px-3 py-2.5"><Routing row={r} /></td>
                  <td className="whitespace-nowrap px-3 py-2.5 text-muted" title={formatDateTime(r.created_at)}>{relativeTime(r.created_at)}</td>
                  {query.bin
                    ? <td className="whitespace-nowrap py-2.5 pl-3 pr-4 text-danger" title={formatDateTime(r.deleted_at)}>{relativeTime(r.deleted_at)}</td>
                    : <td className="whitespace-nowrap py-2.5 pl-3 pr-4 text-muted" title={formatDateTime(r.last_activity_at)}>{relativeTime(r.last_activity_at)}</td>}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div className="flex items-center justify-between gap-3 border-t border-border px-4 py-3 text-[12.5px] text-muted">
        <span><span className="tabular">{rows.length}</span> shown</span>
        {next && (
          <Button variant="secondary" size="sm" onClick={loadMore} disabled={loading}>
            {loading && <LoaderCircle className="size-3.5 animate-spin" />} Load more
          </Button>
        )}
      </div>

      {selected.size > 0 && (
        <div role="region" aria-label="Bulk actions" className="fixed inset-x-0 bottom-5 z-30 mx-auto flex w-fit max-w-[calc(100vw-2rem)] items-center gap-2 rounded-xl border border-border bg-surface px-3 py-2 shadow-xl animate-fade-in">
          <span className="px-1 text-[13px] font-medium text-fg"><span className="tabular">{selected.size}</span> selected</span>
          {passable && (
            <Button size="sm" onClick={() => setPassing(true)}><Send className="size-3.5" /> Pass to CRM</Button>
          )}
          {query.bin ? (
            <Button size="sm" onClick={() => restore(ids)} disabled={restoring}>
              {restoring ? <LoaderCircle className="size-3.5 animate-spin" /> : <RotateCcw className="size-3.5" />} Restore
            </Button>
          ) : (
            <Button variant="danger" size="sm" onClick={() => setDeleting(true)}>
              <Trash2 className="size-3.5" /> Delete
            </Button>
          )}
          <Button variant="ghost" size="icon" className="size-8" aria-label="Clear selection" onClick={() => setSelected(new Set())}>
            <X className="size-4" />
          </Button>
        </div>
      )}

      <DeleteDialog ids={ids} partnerCount={partnerCount} open={deleting} onClose={() => setDeleting(false)} onDone={removeRows} />
      <PassToCrmDialog ids={ids} open={passing} onClose={() => setPassing(false)} onDone={removeRows} />
    </>
  );
}
