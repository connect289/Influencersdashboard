// The lead pipeline as a board (by creator stage) or a table. Rows are creator-safe feed rows: masked contact details,
// whitelisted fields only. Clicking a lead opens the drawer (?lead=<id>).
import Link from "next/link";
import { useTranslations } from "next-intl";
import { Badge } from "@/components/ui/badge";
import { Table, Td, Th } from "@/components/ui/table";
import { CLOSED_STAGES, OPEN_STAGES } from "@/lib/attribution/stages";
import type { FeedRow } from "@/lib/leads/data";
import { formatDate } from "@/lib/format";
import { StageBadge, TemperatureBadge } from "./stage-bits";

type Row = FeedRow & { creator_name?: string };

function leadHref(base: string, query: string, id: string) {
  const u = new URLSearchParams(query);
  u.set("lead", id);
  return `${base}?${u.toString()}`;
}

function Name({ r }: { r: Row }) {
  const t = useTranslations();
  return (
    <span className="font-medium">
      {r.removed ? t("leads.removed") : (r.display_name ?? r.lead_ref)}
    </span>
  );
}

export function LeadBoard({ rows, base, query }: { rows: Row[]; base: string; query: string }) {
  const t = useTranslations();
  const columns = [...OPEN_STAGES, "enrolled", "closed"] as const;
  return (
    <div className="-mx-4 flex snap-x gap-3 overflow-x-auto px-4 pb-2 md:mx-0 md:px-0">
      {columns.map((c) => {
        const items = rows.filter((r) =>
          c === "closed"
            ? (CLOSED_STAGES as readonly string[]).includes(r.creator_stage)
            : r.creator_stage === c,
        );
        return (
          <section
            key={c}
            className="w-64 shrink-0 snap-start rounded-[var(--radius-card)] bg-surface-2 p-2"
            aria-label={t(`leads.columns.${c}`)}
          >
            <h2 className="mb-2 flex items-center justify-between px-1 text-sm font-semibold">
              {t(`leads.columns.${c}`)} <Badge>{items.length}</Badge>
            </h2>
            <ul className="flex flex-col gap-2">
              {items.map((r) => (
                <li key={r.attribution_id}>
                  <Link
                    href={leadHref(base, query, r.attribution_id)}
                    scroll={false}
                    className="block rounded-xl bg-surface p-3 shadow-[var(--shadow-card)] hover:bg-surface-2"
                  >
                    <Name r={r} />
                    <p className="text-xs text-muted">
                      {r.lead_ref} · {formatDate(r.lead_at)}
                    </p>
                    {r.creator_name ? <p className="text-xs text-muted">{r.creator_name}</p> : null}
                    <div className="mt-1 flex flex-wrap items-center gap-1">
                      {c === "closed" ? (
                        <StageBadge stage={r.creator_stage} flags={r.flags} />
                      ) : r.flags.length ? (
                        <StageBadge stage={r.creator_stage} flags={r.flags} />
                      ) : null}
                      <TemperatureBadge value={r.temperature} />
                    </div>
                  </Link>
                </li>
              ))}
            </ul>
          </section>
        );
      })}
    </div>
  );
}

export function LeadTable({
  rows,
  base,
  query,
  staff = false,
}: {
  rows: Row[];
  base: string;
  query: string;
  staff?: boolean;
}) {
  const t = useTranslations();
  return (
    <Table>
      <thead>
        <tr>
          <Th>{t("leads.table.lead")}</Th>
          {staff ? <Th>{t("leads.table.creator")}</Th> : null}
          <Th>{t("leads.table.stage")}</Th>
          <Th>{t("leads.table.programme")}</Th>
          <Th>{t("leads.table.source")}</Th>
          <Th>{t("leads.table.date")}</Th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r) => (
          <tr key={r.attribution_id}>
            <Td>
              <Link
                href={leadHref(base, query, r.attribution_id)}
                scroll={false}
                className="text-primary hover:underline"
              >
                <Name r={r} />
              </Link>
              <span className="block text-xs text-muted">
                {r.lead_ref} · {r.phone_masked}
              </span>
            </Td>
            {staff ? <Td>{r.creator_name}</Td> : null}
            <Td>
              <span className="flex flex-wrap items-center gap-1">
                <StageBadge stage={r.creator_stage} flags={r.flags} />
                <TemperatureBadge value={r.temperature} />
              </span>
              {r.reason_category ? (
                <span className="block text-xs text-muted">{r.reason_category}</span>
              ) : null}
            </Td>
            <Td>
              {typeof r.fields.interested_course === "string" ? r.fields.interested_course : "—"}
            </Td>
            <Td>
              <span className="font-mono text-xs">{r.code}</span>
              {r.deliverable_title ? (
                <span className="block text-xs text-muted">{r.deliverable_title}</span>
              ) : null}
            </Td>
            <Td className="whitespace-nowrap">{formatDate(r.lead_at)}</Td>
          </tr>
        ))}
      </tbody>
    </Table>
  );
}
