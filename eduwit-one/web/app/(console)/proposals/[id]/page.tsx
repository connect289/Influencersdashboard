import { type Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { DecideForm } from "@/components/proposals/decide-form.tsx";
import { appName, riskTone } from "@/components/ui/labels.ts";
import { Badge, SeverityBadge, StatusBadge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Banner, Code, PageHeader } from "@/components/ui/state.tsx";
import { ist, json } from "@/lib/format.ts";
import { requireUser } from "@/lib/session.ts";
import { ui } from "@/lib/ui/api.ts";
import { proposalSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Proposal" };

export default async function ProposalPage({ params }: { params: Promise<{ id: string }> }) {
  const id = Number((await params).id);
  if (!Number.isInteger(id) || id <= 0) notFound();
  const me = await requireUser(`/proposals/${id}`);
  let data;
  try {
    data = await ui("ui_proposal", proposalSchema, { p_id: id });
  } catch (e) {
    return <PageError error={e} />;
  }
  if (!data) notFound();
  const p = data.proposal;
  const decidable = p.status === "open" || p.status === "snoozed";
  // A proposal a fix opened that runs when approved (0019): what runs, and that it runs under the approver's session.
  const change = (p.change ?? {}) as { execute?: { fix?: string; mode?: string; rows?: unknown[] } };
  const runs = p.source === "check" && change.execute?.fix ? change.execute : null;
  const rowCount = runs && Array.isArray(runs.rows) ? runs.rows.length : 0;
  const checked = (p.check_result ?? null) as {
    ran?: boolean;
    ok?: boolean | null;
    why?: string;
    error?: string;
  } | null;
  return (
    <>
      <PageHeader
        title={p.title}
        description={
          <span className="flex flex-wrap items-center gap-2">
            <Badge tone={riskTone[p.risk]}>{p.risk} risk</Badge>
            <Badge>{p.kind}</Badge>
            <StatusBadge status={p.status} />
            {data.owner_only ? <Badge tone="accent">owner approves</Badge> : null}
            <span>
              {appName(p.app)} · from {p.source}
              {p.model ? ` (${p.model})` : ""} · #{p.id}
            </span>
          </span>
        }
      />
      {runs && decidable ? (
        <Banner tone="p2">
          {runs.mode === "approve"
            ? `Approving runs B2B's own retry function for each of the ${rowCount} rows listed, now, under your session.`
            : runs.mode === "app"
              ? `Approving queues ${runs.fix} once; the app runs it within a minute.`
              : `Approving runs ${runs.fix} once, now, with the fixer's rights, on the ${rowCount} rows listed.`}{" "}
          Only rows still failing then are touched. Removing rows from the change below narrows the run; an edit cannot
          add rows. If it runs, the result is checked 10 minutes later and shown here.
        </Banner>
      ) : null}
      {runs && checked ? (
        <Banner tone={checked.ok === true ? "p3" : checked.ok === false ? "p1" : "p2"}>
          {checked.ran === false
            ? `Nothing ran: ${checked.why ?? "see the result below"}. The proposal stays approved.`
            : checked.ok === true
              ? "Checked after the run: every row it touched is done."
              : checked.ok === false
                ? "Checked after the run: some rows are still failing; see the result below."
                : `Checked after the run, but the result could not be read${checked.why || checked.error ? `: ${checked.why ?? checked.error}` : ""}.`}
        </Banner>
      ) : null}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div className="grid min-w-0 content-start gap-4 lg:col-span-2">
          <Card>
            <CardHeader title="Why" />
            <CardBody className="text-sm whitespace-pre-line">{p.rationale}</CardBody>
          </Card>
          <Card>
            <CardHeader
              title="The exact change"
              description="What would be done, and how (an app's own function and its arguments)."
            />
            <CardBody>
              <Code>{json(p.change)}</Code>
            </CardBody>
          </Card>
          {p.simulation ? (
            <Card>
              <CardHeader title="Simulation" />
              <CardBody>
                <Code>{json(p.simulation)}</Code>
              </CardBody>
            </Card>
          ) : null}
          <Card>
            <CardHeader title="Evidence" />
            <CardBody>
              <Code>{json(p.evidence)}</Code>
            </CardBody>
          </Card>
          {p.check_result ? (
            <Card>
              <CardHeader title="Verification after approval" />
              <CardBody>
                <Code>{json(p.check_result)}</Code>
              </CardBody>
            </Card>
          ) : null}
          <Card>
            <CardHeader title="History" />
            <ul className="divide-y divide-border text-sm">
              <li className="px-4 py-2">Created {ist(p.created_at)}</li>
              {data.history.map((h, n) => (
                <li key={n} className="px-4 py-2">
                  {ist(h.at)} · {h.action.replace("proposal.", "")} by {h.actor}
                </li>
              ))}
            </ul>
          </Card>
        </div>
        <div className="order-first grid min-w-0 content-start gap-4 lg:order-none">
          {data.incident ? (
            <Card>
              <CardHeader title="From incident" />
              <CardBody>
                <Link href={`/incidents/${data.incident.id}`} className="flex items-center gap-2 hover:underline">
                  <SeverityBadge severity={data.incident.severity} />
                  {data.incident.title}
                </Link>
              </CardBody>
            </Card>
          ) : null}
          <Card>
            <CardHeader title="Decide" />
            <CardBody>
              {decidable ? (
                <DecideForm
                  id={p.id}
                  change={JSON.stringify(p.change ?? {}, null, 2)}
                  canApprove={!data.owner_only || me.role === "owner"}
                />
              ) : (
                <p className="text-sm">
                  {p.status} by {p.decided_by ?? "—"} {p.decided_at ? `on ${ist(p.decided_at)}` : ""}
                  {p.decision_note ? `: ${p.decision_note}` : ""}
                </p>
              )}
            </CardBody>
          </Card>
        </div>
      </div>
    </>
  );
}
