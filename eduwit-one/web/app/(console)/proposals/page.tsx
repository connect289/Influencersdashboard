import { type Metadata } from "next";
import Link from "next/link";
import { appName, riskTone } from "@/components/ui/labels.ts";
import { Badge, StatusBadge } from "@/components/ui/badge.tsx";
import { buttonClass } from "@/components/ui/button.tsx";
import { Card } from "@/components/ui/card.tsx";
import { Filters, FilterSelect } from "@/components/ui/filters.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Empty, PageHeader } from "@/components/ui/state.tsx";
import { ago } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { pageOf, proposalRowSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Proposals" };

export default async function ProposalsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; kind?: string; before?: string }>;
}) {
  const p = await searchParams;
  const status =
    p.status && ["open", "approved", "rejected", "applied", "expired", "snoozed", "all"].includes(p.status)
      ? p.status
      : "open";
  let page;
  try {
    page = await ui("ui_proposals", pageOf(proposalRowSchema), {
      p_status: status,
      p_kind: p.kind || null,
      p_limit: 100,
      p_before: p.before ? Number(p.before) : null,
    });
  } catch (e) {
    return <PageError error={e} />;
  }
  return (
    <>
      <PageHeader
        title="Proposals"
        description="Fixes, features, config changes and clean-ups waiting for a decision. Approving one that touches money, allocation, live switches, partner mappings, prompts or versioned settings is the owner's."
      />
      <Filters reset="/proposals">
        <FilterSelect
          name="status"
          label="Status"
          value={status}
          options={[
            ["open", "Open"],
            ["snoozed", "Snoozed"],
            ["approved", "Approved"],
            ["rejected", "Rejected"],
            ["applied", "Applied"],
            ["expired", "Expired"],
            ["all", "All"],
          ]}
        />
        <FilterSelect
          name="kind"
          label="Kind"
          value={p.kind}
          options={[
            ["", "Any"],
            ["fix", "Fix"],
            ["config", "Config"],
            ["feature", "Feature"],
            ["cleanup", "Cleanup"],
          ]}
        />
      </Filters>
      <Card>
        {page.rows.length === 0 ? (
          <Empty title="No proposals here">
            {status === "open" ? "Nothing is waiting for a decision." : "Try another status."}
          </Empty>
        ) : (
          <ul className="divide-y divide-border">
            {page.rows.map((r) => (
              <li key={r.id}>
                <Link href={`/proposals/${r.id}`} className="grid gap-1 px-4 py-3 hover:bg-surface-2">
                  <span className="flex flex-wrap items-center gap-2">
                    <Badge tone={riskTone[r.risk]}>{r.risk} risk</Badge>
                    <Badge>{r.kind}</Badge>
                    <StatusBadge status={r.status} />
                    {r.owner_only ? <Badge tone="accent">owner approves</Badge> : null}
                  </span>
                  <span className="font-medium">{r.title}</span>
                  <span className="line-clamp-2 text-sm text-fg-muted">{r.rationale}</span>
                  <span className="text-xs text-fg-muted">
                    {appName(r.app)} · from {r.source} · {ago(r.created_at)}
                    {r.decided_by ? ` · decided by ${r.decided_by}` : ""}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </Card>
      {page.next_before ? (
        <div>
          <Link
            href={`/proposals?status=${status}${p.kind ? `&kind=${p.kind}` : ""}&before=${page.next_before}`}
            className={buttonClass("secondary")}
          >
            Older proposals
          </Link>
        </div>
      ) : null}
    </>
  );
}
