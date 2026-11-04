import Link from "next/link";
import { Badge, StatusBadge } from "@/components/ui/badge.tsx";
import { actionSteps, actionSummary } from "@/components/ui/labels.ts";
import { Code } from "@/components/ui/state.tsx";
import { Table, TBody, TD, TH, THead, TR } from "@/components/ui/table.tsx";
import { ist, json } from "@/lib/format.ts";
import type { ActionRow } from "@/lib/ui/schemas.ts";

/** A fix's history: each row's step, outcome and one line on what it did, with the target and result behind it. */
export function ActionRows({ rows, showFix = false }: { rows: ActionRow[]; showFix?: boolean }) {
  return (
    <Table>
      <THead>
        <TR>
          <TH>When</TH>
          {showFix ? <TH>Fix</TH> : null}
          <TH>Step</TH>
          <TH>What</TH>
          <TH>By</TH>
          <TH>Detail</TH>
        </TR>
      </THead>
      <TBody>
        {rows.map((a) => (
          <TR key={a.id}>
            <TD className="whitespace-nowrap">{ist(a.ran_at)}</TD>
            {showFix ? <TD className="font-medium">{a.fix_id}</TD> : null}
            <TD>
              <span className="flex flex-wrap items-center gap-1">
                <StatusBadge status={a.status} />
                {a.dry_run ? <Badge tone="p3">dry run</Badge> : null}
                <span className="text-xs text-fg-muted">{actionSteps[a.step] ?? a.step}</span>
              </span>
            </TD>
            <TD className="text-sm">
              {actionSummary(a.step, a.status, a.result, a.target)}
              {a.incident_id ? (
                <Link href={`/incidents/${a.incident_id}`} className="block text-xs underline">
                  incident #{a.incident_id}
                </Link>
              ) : null}
              {a.proposal_id ? (
                <Link href={`/proposals/${a.proposal_id}`} className="block text-xs underline">
                  proposal #{a.proposal_id}
                </Link>
              ) : null}
            </TD>
            <TD className="text-xs">{a.ran_by}</TD>
            <TD>
              <details>
                <summary className="cursor-pointer text-xs">target and result</summary>
                <Code className="mt-1">{json({ target: a.target, result: a.result })}</Code>
              </details>
            </TD>
          </TR>
        ))}
      </TBody>
    </Table>
  );
}
