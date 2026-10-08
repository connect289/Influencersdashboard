import Link from "next/link";
import { X } from "lucide-react";
import { cn } from "@/components/ui/cn";
import {
  DESTINATION_LABEL, FLAG_DESTINATIONS, PAID_FILTER_LABEL, PAID_FILTERS, ROUTING_DESTINATIONS, hasFilters, humanize, leadsHref, toggle,
  type Facets, type LeadQuery,
} from "@/lib/leads";

const STATUS_ORDER = ["HOT", "WARM", "COLD", "NONE"];
const STATUS_DOT: Record<string, string> = { HOT: "bg-danger", WARM: "bg-warning", COLD: "bg-info", NONE: "bg-subtle" };
/** The Addendum 3 flags: red for the three the Admin must act on or can never undo, amber for a wait, blue for nurture. */
const FLAG_DOT: Record<string, string> = { barred: "bg-danger", reenquired: "bg-danger", lost_grace: "bg-danger", awaiting_consent: "bg-warning", qualification_nurture: "bg-info" };
const MAX_CHIPS = 8;

/** Values to show for one facet: the most common first, plus anything already selected. */
function options(counts: Record<string, number>, selected: string[], order?: string[]): [string, number][] {
  const entries = Object.entries(counts);
  entries.sort(order ? (a, b) => order.indexOf(a[0]) - order.indexOf(b[0]) : (a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  const shown = entries.slice(0, MAX_CHIPS);
  for (const s of selected) if (!shown.some(([k]) => k === s)) shown.push([s, counts[s] ?? 0]);
  return shown;
}

function Chip({ href, active, count, dot, title, children }: { href: string; active: boolean; count: number; dot?: string; title?: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      scroll={false}
      aria-pressed={active}
      title={title}
      className={cn(
        "inline-flex h-7 items-center gap-1.5 rounded-full border px-2.5 text-[12.5px] transition-colors",
        active ? "border-navy/40 bg-navy text-white dark:border-amber/50 dark:bg-amber/15 dark:text-amber" : "border-border bg-surface text-muted hover:border-border-strong hover:text-fg",
      )}
    >
      {dot && <span className={cn("size-1.5 rounded-full", dot)} aria-hidden />}
      {children}
      <span className={cn("tabular text-[11px]", active ? "opacity-80" : "text-subtle")}>{count}</span>
    </Link>
  );
}

function Group({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label={label}>
      <span className="mr-1 text-[11px] font-medium uppercase tracking-wider text-subtle">{label}</span>
      {children}
    </div>
  );
}

/**
 * Filter chips with live counts (counts follow the search, the test switch and the bin; not each other). Routing and
 * Flags share one single-choice filter (`dest`): a flag is a view of leads in a state, on top of wherever they are.
 */
export function FilterBar({ query, facets }: { query: LeadQuery; facets: Facets }) {
  const status = options(facets.status, query.status, STATUS_ORDER);
  const stage = options(facets.stage, query.stage);
  const source = options(facets.source, query.source);
  const dest = ROUTING_DESTINATIONS.map((d) => [d, facets.destination[d] ?? 0] as const).filter(([d, n]) => n > 0 || query.dest === d);
  const flags = FLAG_DESTINATIONS.map((d) => [d, facets.destination[d] ?? 0] as const).filter(([d, n]) => n > 0 || query.dest === d);
  const paid = PAID_FILTERS.map((p) => [p, facets.paid?.[p] ?? 0] as const).filter(([p, n]) => n > 0 || query.paid === p);
  if (status.length + stage.length + source.length + dest.length + flags.length + paid.length === 0) return null;

  return (
    <div className="flex flex-wrap items-center gap-x-6 gap-y-2.5 border-b border-border bg-surface-2/50 px-4 py-3">
      {status.length > 0 && (
        <Group label="Status">
          {status.map(([k, n]) => (
            <Chip key={k} href={leadsHref(query, { status: toggle(query.status, k) })} active={query.status.includes(k)} count={n} dot={STATUS_DOT[k]}>
              {k === "NONE" ? "No status" : humanize(k)}
            </Chip>
          ))}
        </Group>
      )}
      {stage.length > 0 && (
        <Group label="Stage">
          {stage.map(([k, n]) => (
            <Chip key={k} href={leadsHref(query, { stage: toggle(query.stage, k) })} active={query.stage.includes(k)} count={n}>{humanize(k)}</Chip>
          ))}
        </Group>
      )}
      {source.length > 0 && (
        <Group label="Source">
          {source.map(([k, n]) => (
            <Chip key={k} href={leadsHref(query, { source: toggle(query.source, k) })} active={query.source.includes(k)} count={n}>{humanize(k)}</Chip>
          ))}
        </Group>
      )}
      {dest.length > 0 && (
        <Group label="Routing">
          {dest.map(([k, n]) => (
            <Chip key={k} href={leadsHref(query, { dest: query.dest === k ? null : k })} active={query.dest === k} count={n}>{DESTINATION_LABEL[k]}</Chip>
          ))}
        </Group>
      )}
      {flags.length > 0 && (
        <Group label="Flags">
          {flags.map(([k, n]) => (
            <Chip key={k} href={leadsHref(query, { dest: query.dest === k ? null : k })} active={query.dest === k} count={n} dot={FLAG_DOT[k]}
              title={k === "lost_grace" ? "Marked lost by the partner less than 7 days ago" : k === "barred" ? "Can never go to a partner again" : undefined}>
              {DESTINATION_LABEL[k]}
            </Chip>
          ))}
        </Group>
      )}
      {paid.length > 0 && (
        <Group label="Paid">
          {paid.map(([k, n]) => (
            <Chip key={k} href={leadsHref(query, { paid: query.paid === k ? null : k })} active={query.paid === k} count={n} title="Meta / Google attribution label; no effect on routing">
              {PAID_FILTER_LABEL[k]}
            </Chip>
          ))}
        </Group>
      )}
      {hasFilters({ ...query, q: "" }) && (
        <Link href={leadsHref(query, { stage: [], source: [], status: [], dest: null, paid: null })} scroll={false} className="inline-flex h-7 items-center gap-1 rounded-full px-2 text-[12.5px] text-muted hover:text-fg">
          <X className="size-3.5" /> Clear
        </Link>
      )}
    </div>
  );
}
