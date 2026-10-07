import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { BookOpen, ChevronLeft, Download, History } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Badge, Card, EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import { partnerTitle } from "@/lib/partners";
import { VERSION_LABEL, VERSION_TONE } from "@/lib/programmes";
import { partnerRepo, type VersionSummary } from "@/lib/programmes-data";
import { PartnerLogo } from "../../partners/PartnerLogo";
import { CommissionGst } from "./CommissionGst";
import { OffersTable } from "./OffersTable";
import { SheetSource } from "./SheetSource";
import { UploadWizard } from "./UploadWizard";

type Props = { params: Promise<{ partnerId: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };
const TABS = [{ id: "programmes", label: "Live programmes" }, { id: "versions", label: "Versions" }, { id: "upload", label: "File or sheet" }] as const;
const parseId = (v: string) => (/^\d{1,15}$/.test(v) && Number(v) > 0 ? Number(v) : null);

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const id = parseId((await params).partnerId);
  const r = id ? await partnerRepo(id).catch(() => null) : null;
  return { title: r ? `${partnerTitle(r.partner)} · Programmes` : "Programmes" };
}

function Versions({ partnerId, versions }: { partnerId: number; versions: VersionSummary[] }) {
  if (versions.length === 0) return <EmptyState icon={History} title="No files uploaded yet" />;
  return (
    <ul className="divide-y divide-border">
      {versions.map((v) => {
        const c = v.counts ?? {};
        const review = (c.needs_review ?? 0) + (c.no_match ?? 0);
        return (
          <li key={v.id} className="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3">
            <span className="tabular w-10 text-[13px] font-semibold text-fg">v{v.version_no}</span>
            <div className="min-w-0 flex-1">
              <p className="truncate text-[13px] text-fg">{v.file_name ?? "File"}{v.sheet && v.sheet !== "CSV" ? <span className="text-subtle"> · {v.sheet}</span> : null}</p>
              <p className="text-[12px] text-subtle">
                <span className="tabular">{v.row_count}</span> rows · uploaded <span title={formatDateTime(v.uploaded_at)}>{relativeTime(v.uploaded_at)}</span>
                {v.published_at && <> · published <span title={formatDateTime(v.published_at)}>{relativeTime(v.published_at)}</span></>}
                {v.note && <> · {v.note}</>}
              </p>
            </div>
            <div className="flex flex-wrap items-center gap-1.5">
              <Badge tone={VERSION_TONE[v.status] ?? "neutral"}>{VERSION_LABEL[v.status] ?? v.status}</Badge>
              {v.status === "draft" && review > 0 && <Badge tone="warning"><span className="tabular">{review}</span> to review</Badge>}
              {(c.ignored ?? 0) > 0 && <Badge><span className="tabular">{c.ignored}</span> ignored</Badge>}
            </div>
            <div className="flex items-center gap-1">
              {v.has_file && (
                <a href={`/programmes/files/${v.id}`} className={buttonClass("ghost", "sm")} aria-label={`Download the file of version ${v.version_no}`}><Download className="size-3.5" /></a>
              )}
              {v.status !== "discarded" && (
                <Link href={`/programmes/${partnerId}/versions/${v.id}`} className={buttonClass(v.status === "draft" ? "primary" : "secondary", "sm")}>
                  {v.status === "draft" ? "Review" : v.status === "published" ? "View" : "View or restore"}
                </Link>
              )}
            </div>
          </li>
        );
      })}
    </ul>
  );
}

export default async function PartnerProgrammesPage({ params, searchParams }: Props) {
  await requireAdmin();
  const id = parseId((await params).partnerId);
  if (!id) notFound();
  const repo = await partnerRepo(id);
  if (!repo) notFound();
  const sp = await searchParams;
  const tab = TABS.find((t) => t.id === sp.tab)?.id ?? (repo.offers.length ? "programmes" : repo.versions.length ? "versions" : "upload");
  const p = repo.partner;
  const draft = repo.versions.find((v) => v.status === "draft");
  const live = repo.versions.find((v) => v.status === "published");
  const hasTemplate = Boolean(repo.source && Object.keys(repo.source.column_template ?? {}).length);

  return (
    <>
      <Link href="/programmes" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Programme Repository</Link>
      <div className="mb-5 flex flex-wrap items-center gap-4">
        <PartnerLogo partner={p} size="lg" />
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-xl font-semibold tracking-tight text-fg">{partnerTitle(p)}</h1>
          <p className="text-[13px] text-muted">
            {live ? <>v{live.version_no} live · {repo.offers.length} programmes · published {relativeTime(live.published_at)}</> : "No published programme file"}
          </p>
        </div>
        <Link href={`/partners/${p.id}`} className={buttonClass("secondary", "sm")}>Partner settings</Link>
      </div>

      {sp.published && (
        <p role="status" className="mb-5 rounded-lg border border-success/25 bg-success-bg px-3 py-2 text-[13px] text-success">
          Published. Routing now uses this version for new leads; leads already with a partner stay where they are.
        </p>
      )}
      {draft && tab !== "upload" && (
        <p className="mb-5 flex flex-wrap items-center justify-between gap-2 rounded-lg border border-warning/25 bg-warning-bg px-3 py-2 text-[13px] text-warning">
          Draft v{draft.version_no} is waiting for review and publishing.
          <Link href={`/programmes/${p.id}/versions/${draft.id}`} className="font-medium underline">Review the draft</Link>
        </p>
      )}

      <nav aria-label="Repository sections" className="mb-6 flex gap-5 border-b border-border">
        {TABS.map((t) => (
          <Link key={t.id} href={`/programmes/${p.id}?tab=${t.id}`} aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}>
            {t.label}
            {t.id === "programmes" && <span className="tabular ml-1.5 text-[11px] text-subtle">{repo.offers.length}</span>}
            {t.id === "versions" && <span className="tabular ml-1.5 text-[11px] text-subtle">{repo.versions.length}</span>}
          </Link>
        ))}
      </nav>

      {tab === "programmes" && (
        <Card className="overflow-hidden">
          {repo.offers.length === 0
            ? <EmptyState icon={BookOpen} title="No live programmes" action={<Link href={`/programmes/${p.id}?tab=upload`} className={buttonClass("primary", "sm")}>Upload the partner&apos;s file</Link>}>
                <p>Until a file is published, routing never offers this partner a lead.</p>
              </EmptyState>
            : <>
                {repo.source && repo.offers.some((o) => o.commission) && (
                  <CommissionGst partnerId={p.id} includesGst={repo.source.commission_includes_gst !== false}
                    withCommission={repo.offers.filter((o) => o.commission && o.commission.type !== "tier").length} />
                )}
                <OffersTable offers={repo.offers} />
              </>}
        </Card>
      )}
      {tab === "versions" && <Card><Versions partnerId={p.id} versions={repo.versions} /></Card>}
      {tab === "upload" && (
        p.status === "closed"
          ? <Card><EmptyState icon={BookOpen} title="This partner is closed">Files can no longer be uploaded.</EmptyState></Card>
          : (
            <div className="space-y-6">
              <SheetSource partnerId={p.id} source={repo.source} hasTemplate={hasTemplate} />
              {repo.source?.type !== "gsheet" && <UploadWizard partnerId={p.id} hasTemplate={hasTemplate} />}
            </div>
          )
      )}
    </>
  );
}
