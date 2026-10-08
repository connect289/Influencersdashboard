import type { Metadata } from "next";
import Link from "next/link";
import { Activity, Inbox } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { siteUrl } from "@/lib/env";
import { formatDateTime, relativeTime } from "@/lib/format";
import { OUTLOOK_LABEL, REQUEST_STATUS, SOURCE_LABEL, consentGolive, formCovers } from "@/lib/intake";
import { consentTexts, intakeOverview } from "@/lib/intake-data";
import { Connections } from "./Connections";
import { ConsentTexts } from "./ConsentTexts";
import { Forms } from "./Forms";
import { ImportHistory } from "./ImportHistory";
import { ImportWizard } from "./ImportWizard";
import { NewLead } from "./NewLead";
import { Requests } from "./Requests";

export const metadata: Metadata = { title: "Intake" };

const TABS = [
  { id: "overview", label: "Sources" },
  { id: "import", label: "Import a file" },
  { id: "forms", label: "Ad forms" },
  { id: "consent", label: "Consent texts" },
  { id: "new", label: "New lead" },
  { id: "connections", label: "Connections" },
] as const;
type Tab = (typeof TABS)[number]["id"];

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

function Stat({ label, value, tone, href }: { label: string; value: number; tone?: "danger" | "warning"; href?: string }) {
  const body = (
    <>
      <p className="text-[12px] font-medium text-muted">{label}</p>
      <p className={cn("tabular mt-1 text-2xl font-semibold", value > 0 && tone === "danger" ? "text-danger" : value > 0 && tone === "warning" ? "text-warning" : "text-fg")}>{value.toLocaleString("en-IN")}</p>
    </>
  );
  const cls = "block rounded-[var(--radius-card)] border border-border bg-surface p-4";
  return href ? <Link href={href} className={cn(cls, "transition-colors hover:border-border-strong")}>{body}</Link> : <div className={cls}>{body}</div>;
}

export default async function IntakePage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const tab: Tab = TABS.find((t) => t.id === sp.tab)?.id ?? "overview";
  const [o, texts] = await Promise.all([intakeOverview(), consentTexts()]);
  const today = o.sources.reduce((n, s) => n + s.today, 0);
  const week = o.sources.reduce((n, s) => n + s.week, 0);
  const created = o.sources.reduce((n, s) => n + s.created, 0);
  const heldImports = o.imports.reduce((n, i) => n + i.held, 0);
  // forms that still need a name, or that record partner sharing under a text that does not cover admission partners (D8)
  const formsNeedingWork = o.forms.filter((f) => f.name.startsWith("Meta form ") || f.name.startsWith("Google form ") || formCovers(f, texts) === false).length;
  const golive = consentGolive(texts);
  const resumeId = Number(sp.import);
  const resumeRow = Number.isInteger(resumeId) && resumeId > 0 ? o.imports.find((i) => i.id === resumeId) : undefined;
  const resume = resumeRow ? { id: resumeRow.id, status: resumeRow.status, file_name: resumeRow.file_name } : null;
  const metaOn = o.connections.meta.verify_token && o.connections.meta.app_secret && o.connections.meta.page_token;

  return (
    <>
      <PageHeader title="Intake" description="Every way a lead gets in: Witty, the website, the Intake API, Meta and Google lead forms, file imports and leads typed in by hand. All of them go through lead_intake(), so duplicates merge by phone." />
      <nav className="mb-6 flex gap-5 overflow-x-auto border-b border-border" aria-label="Intake sections">
        {TABS.map((t) => (
          <Link key={t.id} href={`/intake?tab=${t.id}`} aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px shrink-0 whitespace-nowrap border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}>
            {t.label}
            {t.id === "overview" && o.problems.length > 0 && <Badge tone="danger" className="ml-1.5">{o.problems.length}</Badge>}
            {t.id === "forms" && formsNeedingWork > 0 && <Badge tone="warning" className="ml-1.5">{formsNeedingWork}</Badge>}
            {t.id === "consent" && !golive.ok && <Badge tone="warning" className="ml-1.5">{golive.unapproved.length > 0 ? golive.unapproved.length : "!"}</Badge>}
          </Link>
        ))}
      </nav>

      {tab === "overview" && (
        <div className="space-y-6">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Stat label="Leads in today" value={today} />
            <Stat label="New leads, 7 days" value={created} />
            <Stat label="Held for review" value={heldImports + o.held_manual} tone="warning" href="/pool?group=held" />
            <Stat label="Failed or held requests" value={o.problems.length} tone="danger" />
          </div>
          {(!metaOn || !o.connections.google.key || o.connections.api_keys === 0) && (
            <p className="text-[12.5px] text-muted">
              Not connected yet: {[!metaOn && "Meta Lead Ads", !o.connections.google.key && "Google lead forms", o.connections.api_keys === 0 && "the Intake API (no key)"].filter(Boolean).join(", ")}.{" "}
              <Link href="/intake?tab=connections" className="text-info hover:underline">Set up connections</Link>
            </p>
          )}
          <Card className="min-w-0">
            <CardHeader title="Sources, last 7 days" description={`${week.toLocaleString("en-IN")} lead events in all. An event is a new lead or a repeat enquiry that merged into one.`} />
            {o.sources.length === 0 ? <EmptyState icon={Activity} title="No leads in the last 7 days" /> : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[520px] text-left text-[12.5px]">
                  <thead className="text-[11px] uppercase tracking-wider text-subtle">
                    <tr className="border-b border-border">
                      <th scope="col" className="px-5 py-2 font-medium">Source</th>
                      <th scope="col" className="px-3 py-2 text-right font-medium">Today</th>
                      <th scope="col" className="px-3 py-2 text-right font-medium">7 days</th>
                      <th scope="col" className="px-3 py-2 text-right font-medium">New leads</th>
                      <th scope="col" className="px-5 py-2 font-medium">Last</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {o.sources.map((s) => (
                      <tr key={s.source}>
                        <td className="px-5 py-2 font-medium text-fg">{SOURCE_LABEL[s.source] ?? s.source}</td>
                        <td className="tabular px-3 py-2 text-right">{s.today}</td>
                        <td className="tabular px-3 py-2 text-right">{s.week}</td>
                        <td className="tabular px-3 py-2 text-right">{s.created}</td>
                        <td className="px-5 py-2 text-muted" title={formatDateTime(s.last_at)}>{relativeTime(s.last_at)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
          <Card className="min-w-0">
            <CardHeader title={`Needs attention (${o.problems.length})`} description="Leads from the API, Meta and Google that could not be stored. Meta leads can be fetched again." />
            <Requests rows={o.problems} />
          </Card>
          <Card className="min-w-0">
            <CardHeader title="Latest requests" description="The last 60 leads received by the API, Meta, Google and manual entry, with where each is heading." />
            {o.recent.length === 0 ? <EmptyState icon={Inbox} title="Nothing received yet">Imports are listed under Import a file; Witty&apos;s leads under Leads.</EmptyState> : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[680px] text-left text-[12.5px]">
                  <thead className="text-[11px] uppercase tracking-wider text-subtle">
                    <tr className="border-b border-border">
                      <th scope="col" className="px-5 py-2 font-medium">When</th>
                      <th scope="col" className="px-3 py-2 font-medium">Source</th>
                      <th scope="col" className="px-3 py-2 font-medium">Lead</th>
                      <th scope="col" className="px-3 py-2 font-medium">Status</th>
                      <th scope="col" className="px-5 py-2 font-medium">Heading to</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {o.recent.map((q) => (
                      <tr key={q.id}>
                        <td className="whitespace-nowrap px-5 py-2 text-muted" title={formatDateTime(q.received_at)}>{relativeTime(q.received_at)}</td>
                        <td className="px-3 py-2">{SOURCE_LABEL[q.source] ?? q.source}{q.is_test && <Badge tone="brand" className="ml-1.5">test</Badge>}</td>
                        <td className="px-3 py-2">{q.lead_id ? <Link href={`/leads?lead=${q.lead_id}`} className="text-fg hover:underline">{q.name ?? `#${q.lead_id}`}</Link> : <span className="text-subtle">—</span>}
                          {q.action && q.action !== "created" && <span className="ml-1.5 text-[11.5px] text-subtle">{q.action}</span>}</td>
                        <td className="px-3 py-2"><Badge tone={REQUEST_STATUS[q.status]?.tone ?? "neutral"}>{REQUEST_STATUS[q.status]?.label ?? q.status}</Badge></td>
                        <td className="px-5 py-2 text-muted">{q.routing ? <>{OUTLOOK_LABEL[q.routing.outlook] ?? q.routing.outlook}{q.routing.status === "waiting" && q.routing.waiting_for?.length > 0 && <span className="text-subtle"> · waits for {q.routing.waiting_for.join(", ")}</span>}</> : q.error ?? ""}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </div>
      )}

      {tab === "import" && (
        <div className="space-y-6">
          <Card className="min-w-0">
            <CardHeader title="Import a file" description="Upload, map the columns, check the courses and duplicates, then record the consent basis and choose where the leads go. Nothing is written until the last step." />
            <ImportWizard key={resume?.id ?? "new"} templates={o.templates} resume={resume} />
          </Card>
          <Card className="min-w-0">
            <CardHeader title="Imports" description="The last 30. New leads can be rolled back for 24 hours if nothing has routed them yet." />
            <ImportHistory rows={o.imports} />
          </Card>
        </div>
      )}

      {tab === "forms" && (
        <Card className="min-w-0">
          <CardHeader title="Meta and Google lead forms"
            description="How each form's questions map to lead fields, fixed values for single-programme forms, and the consent the form shows. A form that records partner sharing must name a registered consent text that covers our admission partners (edtech companies); leads from forms without it are asked for consent before routing." />
          <Forms forms={o.forms} texts={texts} />
        </Card>
      )}

      {tab === "consent" && (
        <Card className="min-w-0">
          <CardHeader title="Consent texts" description="The wording each channel shows when a student agrees, by version. Which versions cover sharing with our admission partners, and which the lawyer has approved: the approval is a routing go-live condition." />
          <ConsentTexts texts={texts} />
        </Card>
      )}

      {tab === "new" && (
        <Card className="min-w-0">
          <CardHeader title="New lead" description="A lead from a call, walk-in or event. If the phone is already known, the details are added to that lead; other courses the student mentioned become secondary interests." />
          <NewLead texts={texts} />
        </Card>
      )}

      {tab === "connections" && (
        <Card className="min-w-0">
          <CardHeader title="Connections" description="Webhook addresses and secrets for Meta and Google, and the Intake API. Secrets are stored in the database vault and never shown again." />
          <Connections c={o.connections} site={siteUrl()} />
        </Card>
      )}
    </>
  );
}
