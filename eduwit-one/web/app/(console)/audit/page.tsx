import { type Metadata } from "next";
import Link from "next/link";
import { buttonClass } from "@/components/ui/button.tsx";
import { Badge, StatusBadge } from "@/components/ui/badge.tsx";
import { Card } from "@/components/ui/card.tsx";
import { Filters, FilterSelect } from "@/components/ui/filters.tsx";
import { Input } from "@/components/ui/field.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Code, Empty, PageHeader } from "@/components/ui/state.tsx";
import { Table, TBody, TD, TH, THead, TR } from "@/components/ui/table.tsx";
import { inr, ist, json, ms, num, usd } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { aiCallsSchema, auditSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Audit" };

export default async function AuditPage({
  searchParams,
}: {
  searchParams: Promise<{ kind?: string; q?: string; before?: string }>;
}) {
  const p = await searchParams;
  const kind = p.kind === "ai_calls" ? "ai_calls" : "audit";
  const args = { p_kind: kind, p_q: p.q?.trim() || null, p_limit: 100, p_before: p.before ? Number(p.before) : null };
  let audit = null;
  let calls = null;
  try {
    if (kind === "audit") audit = await ui("ui_audit", auditSchema, args);
    else calls = await ui("ui_audit", aiCallsSchema, args);
  } catch (e) {
    return <PageError error={e} />;
  }
  const page = audit ?? calls ?? { rows: [], next_before: null };
  const qs = (extra: Record<string, string>) =>
    new URLSearchParams({ kind, ...(p.q ? { q: p.q } : {}), ...extra }).toString();
  return (
    <>
      <PageHeader
        title="Audit"
        description="Every write through the app (who, what, the request id) and every AI model call (tokens, cost, latency)."
        actions={
          <a href={`/audit/export?${qs({})}`} className={buttonClass("secondary", "sm")}>
            Export CSV
          </a>
        }
      />
      <Filters reset="/audit">
        <FilterSelect
          name="kind"
          label="Log"
          value={kind}
          options={[
            ["audit", "Writes (one.audit)"],
            ["ai_calls", "AI calls (one.ai_calls)"],
          ]}
        />
        <label className="grid gap-1 text-xs text-fg-muted">
          Search
          <Input
            name="q"
            defaultValue={p.q}
            placeholder={kind === "audit" ? "actor, action or target" : "model or purpose"}
            className="min-h-9 py-1"
          />
        </label>
      </Filters>
      <Card>
        {page.rows.length === 0 ? (
          <Empty title="Nothing recorded yet" />
        ) : audit ? (
          <Table>
            <THead>
              <TR>
                <TH>When</TH>
                <TH>Who</TH>
                <TH>What</TH>
                <TH>Target</TH>
                <TH>Detail</TH>
              </TR>
            </THead>
            <TBody>
              {audit.rows.map((r) => (
                <TR key={r.id}>
                  <TD className="whitespace-nowrap">{ist(r.at)}</TD>
                  <TD className="text-xs">{r.actor}</TD>
                  <TD>
                    <Badge>{r.action}</Badge>
                  </TD>
                  <TD className="text-xs">{r.target}</TD>
                  <TD>
                    {r.before != null || r.after != null ? (
                      <details>
                        <summary className="cursor-pointer text-xs">
                          before / after{r.request_id ? ` · ${r.request_id.slice(0, 8)}` : ""}
                        </summary>
                        <Code className="mt-1">{json({ before: r.before, after: r.after })}</Code>
                      </details>
                    ) : (
                      <span className="text-xs text-fg-muted">{r.request_id?.slice(0, 8)}</span>
                    )}
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
        ) : calls ? (
          <Table>
            <THead>
              <TR>
                <TH>When</TH>
                <TH>Model</TH>
                <TH>Purpose</TH>
                <TH className="text-right">Tokens in / out</TH>
                <TH className="text-right">Cost</TH>
                <TH className="text-right">Took</TH>
                <TH>Result</TH>
              </TR>
            </THead>
            <TBody>
              {calls.rows.map((r) => (
                <TR key={r.id}>
                  <TD className="whitespace-nowrap">{ist(r.created_at)}</TD>
                  <TD className="text-xs">
                    {r.provider} · {r.model}
                  </TD>
                  <TD>{r.purpose}</TD>
                  <TD className="text-right tabular-nums">
                    {num(r.input_tokens)} / {num(r.output_tokens)}
                  </TD>
                  <TD className="text-right tabular-nums">{r.cost_inr != null ? inr(r.cost_inr) : usd(r.cost_usd)}</TD>
                  <TD className="text-right tabular-nums">{ms(r.latency_ms)}</TD>
                  <TD>
                    <StatusBadge status={r.ok ? "ok" : "failed"} />
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
        ) : null}
      </Card>
      {page.next_before ? (
        <div>
          <Link href={`/audit?${qs({ before: String(page.next_before) })}`} className={buttonClass("secondary")}>
            Older entries
          </Link>
        </div>
      ) : null}
    </>
  );
}
