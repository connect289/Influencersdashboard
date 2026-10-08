"use client";
import { useEffect, useId, useRef, useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowDown, ArrowUp, ArrowUpDown, BellOff, FlaskConical, Forward, LoaderCircle, Repeat, RotateCcw, Send, Trash2, X } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { formatDateTime, relativeTime } from "@/lib/format";
import {
  bulkRouteToast, formatPhone, humanize, leadsHref, reroutePreview, rerouteToast, rowBadges, sendToPartnersPreview, statusTone,
  type LeadPage, type LeadQuery, type LeadRow, type Sort,
} from "@/lib/leads";
import type { Lane } from "@/lib/routing";
import { loadMoreLeads, rerouteMany, routeToPartnersMany } from "./actions";
import { DeleteDialog, useRestore } from "./LeadMutations";
import { PassToCrmDialog } from "./PassToCrm";

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

/** Destination and the Addendum 3 flags of a row (lib/leads rowBadges); the hover title carries the long form. */
function Routing({ row }: { row: LeadRow }) {
  const badges = rowBadges(row);
  const unrouted = !row.destination_type && !row.not_passed;
  if (badges.length === 0) return <span className="text-subtle">Not routed</span>;
  return (
    <span className="flex flex-wrap items-center gap-1">
      {unrouted && <span className="text-subtle">Not routed</span>}
      {badges.map((b) => (
        <span key={b.key} title={b.title}>
          <Badge tone={b.tone} className="whitespace-nowrap">{b.text}</Badge>
        </span>
      ))}
    </span>
  );
}

const plural = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;

/**
 * Bulk 'Send to partners' (PART 6.3): every selected lead is offered to b2b.route_to_partners_many, which skips
 * partner-barred leads, leads without partner-sharing consent and leads B2C does not hold, and counts each kind. The
 * counts the rows already show are listed up front so the Admin knows before confirming.
 */
function SendToPartnersDialog({ rows, open, onClose, onDone }: { rows: LeadRow[]; open: boolean; onClose: () => void; onDone: () => void }) {
  const p = sendToPartnersPreview(rows);
  const skips = [
    p.barred > 0 && `${p.barred} partner-barred`,
    p.no_consent > 0 && `${p.no_consent} without partner-sharing consent`,
    p.not_held > 0 && `${p.not_held} not with B2C`,
  ].filter((s): s is string => Boolean(s));
  return (
    <ConfirmDialog
      open={open}
      onClose={onClose}
      title={rows.length === 1 ? "Send this lead to partners?" : `Send ${rows.length} leads to partners?`}
      confirmLabel="Send to partners"
      reason={{ label: "Reason (required, kept in the audit log)", placeholder: "e.g. the student asked for a partner; B2C has no capacity this week" }}
      onConfirm={async (reason) => {
        if (p.sendable === 0) return `None of the selected leads can be sent: ${skips.join(", ")}.`;
        const r = await routeToPartnersMany(rows.map((x) => x.id), reason);
        if (!r.ok) return r.error;
        const text = bulkRouteToast(r.counts);
        if ((r.counts.sent ?? 0) > 0) toast.success(text); else toast.warning(text);
        onDone();
      }}
    >
      <p>
        Each lead goes through partner routing by hand: the best eligible partner takes it, a lead without consent is asked first, and a lead no partner can
        take returns to its B2C counsellor. Partner-barred leads (duplicate at partners or lost by a partner) can never go to a partner and are skipped with a count.
      </p>
      <p className="mt-2">
        <span className="font-medium text-fg">{p.sendable} of {rows.length}</span> can be sent.
        {skips.length > 0 && <span className="text-warning"> Skipped: {skips.join(" · ")}.</span>}
      </p>
    </ConfirmDialog>
  );
}

/**
 * Bulk 'Re-route' (PART 6.2): recalls partner-held leads to B2C (sales or nurture) or to another partner through
 * b2b.reroute_many. The database allows a recall only before the partner's first contact attempt or after an SLA
 * breach, skips leads lost in grace, and refuses partners for partner-barred leads; every skip is counted in the toast.
 */
function RerouteDialog({ rows, open, onClose, onDone }: { rows: LeadRow[]; open: boolean; onClose: () => void; onDone: () => void }) {
  const id = useId();
  const [to, setTo] = useState<"b2c" | "partners">("b2c");
  const [lane, setLane] = useState<Lane>("sales");
  const p = reroutePreview(rows, to);
  const skips = [
    p.lost_in_grace > 0 && `${p.lost_in_grace} lost, in grace`,
    p.barred > 0 && `${p.barred} partner-barred (B2C only)`,
    p.not_with_partner > 0 && `${p.not_with_partner} not with a partner`,
  ].filter((s): s is string => Boolean(s));
  const radio = "size-4 accent-[var(--primary)]";
  return (
    <ConfirmDialog
      open={open}
      onClose={onClose}
      title={rows.length === 1 ? "Re-route this lead?" : `Re-route ${rows.length} leads?`}
      confirmLabel="Re-route"
      reason={{ label: "Reason (required by the rulebook, sent to the partner)", placeholder: "e.g. no contact attempt in 3 working days" }}
      onConfirm={async (reason) => {
        if (p.candidates === 0) return `None of the selected leads can be re-routed: ${skips.join(", ")}.`;
        const r = await rerouteMany(rows.map((x) => x.id), to, reason, to === "b2c" ? lane : undefined);
        if (!r.ok) return r.error;
        const text = rerouteToast(r.counts);
        if ((r.counts.done ?? 0) > 0) toast.success(text); else toast.warning(text);
        onDone();
      }}
    >
      <fieldset className="space-y-1.5">
        <legend className="mb-1 text-[13px] font-medium text-fg">Where to</legend>
        <label className="flex items-center gap-2 text-fg">
          <input type="radio" name={`${id}-to`} className={radio} checked={to === "b2c"} onChange={() => setTo("b2c")} /> B2C counsellors
        </label>
        {to === "b2c" && (
          <div className="ml-6 flex flex-wrap gap-4 text-[12.5px]">
            <label className="flex items-center gap-1.5"><input type="radio" name={`${id}-lane`} className={radio} checked={lane === "sales"} onChange={() => setLane("sales")} /> Sales lane (assigned now)</label>
            <label className="flex items-center gap-1.5"><input type="radio" name={`${id}-lane`} className={radio} checked={lane === "nurture"} onChange={() => setLane("nurture")} /> Nurture lane</label>
          </div>
        )}
        <label className="flex items-center gap-2 text-fg">
          <input type="radio" name={`${id}-to`} className={radio} checked={to === "partners"} onChange={() => setTo("partners")} /> Another partner (the current one is excluded)
        </label>
      </fieldset>
      <p className="mt-3">
        A partner can be recalled only before its first contact attempt or after an SLA breach; the database checks each lead and skips the rest with a count.
        Leads lost less than 7 days ago stay with their partner. A re-route to B2C does not bar the lead from partners.
      </p>
      <p className="mt-2">
        <span className="font-medium text-fg">{p.candidates} of {rows.length}</span> can be recalled.
        {skips.length > 0 && <span className="text-warning"> Skipped: {skips.join(" · ")}.</span>}
      </p>
    </ConfirmDialog>
  );
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
  const [sending, setSending] = useState(false);
  const [rerouting, setRerouting] = useState(false);
  // After a bulk routing action the badges of the rows change in place: the next server refresh replaces the loaded rows.
  // Only then (opening the drawer also re-renders the page, and must not collapse the pages loaded so far).
  const syncOnRefresh = useRef(false);
  useEffect(() => {
    if (!syncOnRefresh.current) return;
    syncOnRefresh.current = false;
    setRows(initial.rows);
    setNext(initial.next);
  }, [initial]);

  const removeRows = (ids: number[]) => {
    if (!ids.length) return;
    const gone = new Set(ids);
    setRows((r) => r.filter((x) => !gone.has(x.id)));
    setSelected((s) => new Set([...s].filter((id) => !gone.has(id))));
    router.refresh(); // counts and facets
  };
  const { restore, pending: restoring } = useRestore(removeRows);
  const routed = () => {
    setSelected(new Set());
    syncOnRefresh.current = true;
    router.refresh();
  };

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
  const sel = rows.filter((r) => selected.has(r.id));
  const partnerCount = sel.filter((r) => r.destination_type === "partner").length;
  const passable = !query.bin && sel.length > 0 && sel.every((r) => r.not_passed);
  const held = sel.filter((r) => !r.not_passed && r.destination_type === "in_house");
  const withPartner = sel.filter((r) => !r.not_passed && r.destination_type === "partner");
  const canSend = !query.bin && held.length > 0;
  const canReroute = !query.bin && withPartner.length > 0;
  const mix = [held.length > 0 && `${held.length} with B2C`, withPartner.length > 0 && `${withPartner.length} with a partner`].filter(Boolean).join(" · ");

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
                  <td className="max-w-[360px] px-3 py-2.5"><Routing row={r} /></td>
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
        <div role="region" aria-label="Bulk actions" className="fixed inset-x-0 bottom-5 z-30 mx-auto flex w-fit max-w-[calc(100vw-2rem)] flex-wrap items-center gap-2 rounded-xl border border-border bg-surface px-3 py-2 shadow-xl animate-fade-in">
          <span className="px-1 text-[13px] font-medium text-fg">
            <span className="tabular">{selected.size}</span> selected
            {mix && !query.bin && <span className="ml-1.5 text-[12px] font-normal text-subtle">{mix}</span>}
          </span>
          {passable && (
            <Button size="sm" onClick={() => setPassing(true)}><Send className="size-3.5" /> Pass to CRM</Button>
          )}
          {canSend && (
            <Button size="sm" variant={passable ? "secondary" : "primary"} onClick={() => setSending(true)} title={`${plural(held.length, "B2C-held lead")} selected`}>
              <Forward className="size-3.5" /> Send to partners
            </Button>
          )}
          {canReroute && (
            <Button size="sm" variant="secondary" onClick={() => setRerouting(true)} title={`${plural(withPartner.length, "partner-held lead")} selected`}>
              <Repeat className="size-3.5" /> Re-route
            </Button>
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
      <SendToPartnersDialog rows={sel} open={sending} onClose={() => setSending(false)} onDone={routed} />
      <RerouteDialog rows={sel} open={rerouting} onClose={() => setRerouting(false)} onDone={routed} />
    </>
  );
}
